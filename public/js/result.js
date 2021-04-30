const TILES_URL = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
const ATTRIBUTION = 'Tiles by OpenStreetMap';
const MAP_ID = 'map';
const DEFAULT_POSITION = [51.505, -0.09];
const DEFAULT_ZOOM = 5;
const FEATURE_COLLECTION = 'FeatureCollection'
const POINT = 'Point'
const POLYLINE = 'LineString'
const POLYGON = 'Polygon'

var map;
var queryParams;
const layers = {}

function forEachLayers(callback) {
  Object.keys(layers).forEach(function(layerName) {
    callback(layerName);
  });
}

function getQueryParams() {
  let query = window.location.search

  if (query[0] === '?') {
    query = query.substring(1);
  }
  query = decodeURIComponent(query);

  return query.split('&').reduce(function(object, param) {
    const splitQuery = param.split('=');
    object[splitQuery[0]] = splitQuery[1];
    return object
  }, {});
};

function toggleLoading() {
  $('body').toggleClass('loading');
  $('#map').toggleClass('loading');
}

function switchCluster() {
  forEachLayers(function(layerName) {
    const layerInfos = layers[layerName];
    if (layerInfos.type === POINT && (map.hasLayer(layerInfos.layer) || map.hasLayer(layerInfos.cluster))) {
      if (window.leafletOptions.showClusters) {
        map.removeLayer(layerInfos.layer);
        map.addLayer(layerInfos.cluster);
      } else {
        map.removeLayer(layerInfos.cluster);
        map.addLayer(layerInfos.layer);
      }
    }
  })
}

function showJobOnMap(body) {
  let isFitBound = false;
  if (body.geojsons) {
    const geojson = body.geojsons[body.geojsons.length - 1]
    parseGeojsonObject(geojson, '');
    forEachLayers(function(layerName) {
      if (!isFitBound && layers[layerName].type === POINT) {
        map.fitBounds(window.leafletOptions.showClusters ? layers[layerName].cluster.getBounds() : layers[layerName].layer.getBounds())
      }
    });
  }
}

function resetPage() {
  $('#checkbox-container').empty();
  forEachLayers(function(layerName) {
    const layerInfos = layers[layerName];
    let layer;
    if (layerInfos.type === POINT) {
      layer = window.leafletOptions.showClusters ? layerInfos.cluster : layerInfos.layer;
    } else {
      layer = layerInfos.layer;
    }
    if (map.hasLayer(layer)) {
      map.removeLayer(layer);
    }
  })
}

function getJob(job_id, api_key) {
  resetPage();
  toggleLoading();
  $.ajax({
    type: 'GET',
    url: '/0.1/vrp/jobs/' + job_id + '.json',
    data: {api_key: api_key},
    success: showJobOnMap,
    error: function(xhr) {
      console.error(xhr);
    },
    complete: toggleLoading
  })
}

function createCheckbox(layerName) {
  const label = layerName.split('.').join(' - ');
  const id = layerName.split('.').join('_');
  const html =
      '<div class="block">' +
      '<input type="checkbox" id="' + id + '"/>' +
      '<label for="' + id + '">' + label + '</label>' +
      '</div>';
  $('#checkbox-container').append(html);
  $('#' + id).on('click', function(e) {
    let layer = layers[layerName].layer;
    if (layers[layerName].type === POINT) {
      layer = window.leafletOptions.showClusters ? layers[layerName].cluster : layers[layerName].layer;
    }
    if (e.target.checked) {
      map.addLayer(layer);
    } else {
      map.removeLayer(layer);
    }
  });
}

function createPopupContent(properties) {
  return Object.keys(properties).map(key => {
    let content = '';
    if (key === 'duration') {
      const duration = new Date(0);
      duration.setSeconds(properties[key]);
      content += '<div>duration : ' + duration.toLocaleTimeString() + '</div>'
    } else if (key !== 'color') {
      content += '<div>' + key + ' : ' + properties[key] + '</div>'
    }
    return content;
  }).join('');
}

function createPointLayer(featuresCollection, key, featureType) {
  layers[key] = { layer: new L.featureGroup(), cluster: new L.markerClusterGroup(), type: featureType };

  new L.geoJSON(featuresCollection, {
    pointToLayer: function(geoJsonPoint, latlng) {
      const marker = L.marker(latlng, {
        icon: L.divIcon({html: '<span class="circle" style="background-color: '+ geoJsonPoint.properties.color + ';"/>'}),
      });
      marker.bindPopup(createPopupContent(geoJsonPoint.properties));
      return marker;
    }
  }).addTo(layers[key].layer).addTo(layers[key].cluster);
}

function createLayer(featuresCollection, key, featureType) {
  layers[key] = { layer: new L.layerGroup(), type: featureType }
  new L.geoJSON(featuresCollection, {
    onEachFeature: function (feature, layer) {
      layer.setStyle({
        color: feature.properties.color
      });
      layer.bindPopup(createPopupContent(feature.properties));
    }
  }).addTo(layers[key].layer)
}

function getFeatureType(featuresCollection) {
  if (featuresCollection.features) {
    return featuresCollection.features[0].geometry.type;
  }
  return null;
}

function parseGeojsonObject(obj, parent) {
  const featureType = getFeatureType(obj);
  if (obj.type === FEATURE_COLLECTION) {
    featureType === POINT ? createPointLayer(obj, parent, featureType) : createLayer(obj, parent, featureType);
    createCheckbox(parent);
    return [parent];
  } else {

    Object.keys(obj).forEach(key => {
      if (typeof obj[key] === 'object') {
        const newKey = parent + (parent.length > 0 ? '.' : '') + key;
        parseGeojsonObject(obj[key], newKey);
      }
    });

  }
}

function handleBack() {
  window.location.replace(window.location.origin + '?api_key=' + queryParams.api_key)
}

function initializeMap(id) {
  const map = L.map(id).setView(DEFAULT_POSITION, DEFAULT_ZOOM);

  L.tileLayer(TILES_URL, {
    attribution: ATTRIBUTION
  }).addTo(map);

  L.Control.clustersControl({ position: 'topleft', onSwitch: switchCluster }).addTo(map);

  return map;
}

function initializeHandlers() {
  $('#get-job').on('click', function() { getJob($('#job-id').val(), queryParams.api_key) });
  $('#back').on('click', handleBack);
}

function initialize() {
  map = initializeMap(MAP_ID);
  queryParams = getQueryParams();

  if (queryParams.job_id) {
    $('#job-id').val(queryParams.job_id);
    getJob(queryParams.job_id, queryParams.api_key);
  }
  initializeHandlers();
}

$(document).ready(initialize);
