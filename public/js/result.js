const TILES_URL = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
const ATTRIBUTION = 'Tiles by OpenStreetMap';
const MAP_ID = 'map';
const DEFAULT_POSITION = [51.505, -0.09];
const DEFAULT_ZOOM = 5;

var map;
var oms;
var queryParams;
const layers = {
  partitionsVehicle: new L.layerGroup(),
  partitionsWorkDay: new L.layerGroup(),
  points:new L.featureGroup(),
  polylines: new L.layerGroup()
}

const popupContent = {
  partitions: function(properties) {
    const duration = new Date(0);
    duration.setSeconds(properties.duration);
    return  (
      '<div>name : ' + properties.name + '</div>' +
      '<div>nbr : ' + properties.nbr + '</div>' +
      '<div>duration : ' + duration.toLocaleTimeString() + '</div>'
    );
  },
  polylines: function(properties) {
    return  (
      '<div>name : ' + properties.name + '</div>' +
      '<div>day : ' + properties.day + '</div>' +
      '<div>vehicle : ' + properties.vehicle + '</div>'
    );
  }
}

const layerInitializers = {
  partitions: function(geojson) {
    ['vehicle', 'work_day'].forEach(function (key, idx) {
      if (geojson[key]) {
        new L.geoJSON(geojson[key]['features'], {
          onEachFeature: function (feature, layer) {
            layer.setStyle({
              color: feature.properties.color
            });
            layer.bindPopup(popupContent['partitions'](feature.properties));
          }
        }).addTo(idx ? layers['partitionsWorkDay'] : layers['partitionsVehicle'])
      }
    });
  },

  points: function(geojson) {
    new L.geoJSON(geojson['features'], {
      pointToLayer: function(geoJsonPoint, latlng) {
        const marker = L.marker(latlng, {
          icon: L.divIcon({html: '<span class="circle" style="background-color: '+ geoJsonPoint.properties.color + ';"/>'}),
          title: geoJsonPoint.properties.name + (geoJsonPoint.properties.day ? ' (day : ' + geoJsonPoint.properties.day + ')' : '')
        });
        oms.addMarker(marker);
        return marker;
      }
    }).addTo(layers['points']);
  },

  polylines: function(geojson) {
    new L.geoJSON(geojson['features'], {
      onEachFeature: function (feature, layer) {
        layer.setStyle({
          color: feature.properties.color
        });
        layer.bindPopup(popupContent['polylines'](feature.properties));
      }
    }).addTo(layers['polylines'])
  }
}

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
};

function setCheckboxesVisibility(geojson) {
  Object.keys(layers).forEach(function (layerName) {
    if (geojson['partitions'] && (layerName === 'partitionsVehicle' && geojson['partitions']['vehicle']
      || layerName === 'partitionsWorkDay' && geojson['partitions']['work_day'])) {
      $('#' + layerName).fadeIn();
    }
    else if (geojson[layerName]) {
      $('#' + layerName).fadeIn();
    } else {
      $('#' + layerName).fadeOut();
    }
  });
}

function getLayersToShow() {
  return Object.keys(layers).reduce(function(object, key) {
    object[key] = $('#' + key + '-checkbox').get(0).checked
    return object;
  }, {});
}

function setLayersToShow() {
  const layersToShow = getLayersToShow();

  forEachLayers(function(layerName) {
    if (layersToShow[layerName]) {
      map.addLayer(layers[layerName]);
    } else {
      map.removeLayer(layers[layerName]);
    }
  });
}

function showJobOnMap(body) {
  if (body.geojsons) {
    const geojson = body.geojsons[body.geojsons.length - 1]

    setCheckboxesVisibility(geojson);
    Object.keys(geojson).forEach(function (key) {
      layerInitializers[key](geojson[key])
    });

    setLayersToShow();
    map.fitBounds(layers['points'].getBounds())
  }
}

function clearLayers() {
  forEachLayers(function(layerName) {
    layers[layerName].clearLayers();
  });
}

function resetCheckBoxes() {
  forEachLayers(function(layerName) {
    $('#' + layerName + '-checkbox')[0].checked = false;
  });
}

function getJob(job_id, api_key) {
  clearLayers();
  resetCheckBoxes();
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

function handleBack() {
  window.location.replace(window.location.origin + '?api_key=' + queryParams.api_key)
}

function handleLayers(name) {
  return function(e) {
    const layer = layers[name]
    if (e.target.checked) {
      map.addLayer(layer);
    } else {
      map.removeLayer(layer);
    }
  }
}

function initializeMap(id) {
  const map = L.map(id).setView(DEFAULT_POSITION, DEFAULT_ZOOM);

  L.tileLayer(TILES_URL, {
    attribution: ATTRIBUTION
  }).addTo(map);

  return map;
}

function initializeHandlers() {
  $('#get-job').on('click', function() { getJob($('#job-id').val(), queryParams.api_key); });
  $('#back').on('click', handleBack);
  forEachLayers(function(layerName) {
    $('#' + layerName + '-checkbox').on('change', handleLayers(layerName));
  });
}

function initialize() {
  map = initializeMap(MAP_ID);
  oms= new OverlappingMarkerSpiderfier(map);
  queryParams = getQueryParams();

  if (queryParams.job_id) {
    $('#job-id').val(queryParams.job_id);
    getJob(queryParams.job_id, queryParams.api_key);
  }
  initializeHandlers();
}

$(document).ready(initialize);
