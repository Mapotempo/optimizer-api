const TILES_URL = 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png';
const ATTRIBUTION = 'Tiles by OpenStreetMap';
const MAP_ID = 'map';
const DEFAULT_POSITION = [51.505, -0.09];
const DEFAULT_ZOOM = 5;

var map;
var queryParams;
var layers = {}
var dayMap = [ 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun' ]
const colorByVehicle = {};

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
  const layerNames = $('#vehicle-select').select2('data').map(option => option.id);
  clearLayers(layers);
  showLayersOnMap(layerNames);
  fitBounds(layerNames);
}

function getCheckboxesState() {
  const states = { points: false, polylines: false, partitionsWorkDay: false, partitionsVehicle: false };
  $('#checkbox-container input').each((i, checkbox) => {
    states[checkbox.id] = checkbox.checked;
  });
  return states;
}

function showLayersOnMap(layerNames) {
  const checkboxesState = getCheckboxesState();

  layerNames.forEach(layerName => {
    Object.keys(checkboxesState).forEach(key => {
      if (checkboxesState[key] && key === 'points' && window.leafletOptions.showClusters) {
        layers[layerName]['clusters'].addTo(map);
      }
      else if (checkboxesState[key]) {
        layers[layerName][key].addTo(map);
      }
    })
  })
}

function fitBounds(layerNames) {
  if (layerNames < 1) {
    return;
  }
  const featureGroup = new L.featureGroup();
  layerNames.forEach(name => {
    layers[name].points.addTo(featureGroup)
  })
  map.fitBounds(featureGroup.getBounds());
}

function setup(body) {
  if (body.geojsons) {
    const geojson = body.geojsons[body.geojsons.length - 1]
    const parsedGeojson = parseGeojson(geojson);

    layers = parsedGeojsonToLayers(parsedGeojson);
    createSelect2(Object.keys(layers), (layerNames) => {
      clearLayers(layers);
      showLayersOnMap(layerNames);
      fitBounds(layerNames);
    });
    createColorsSelectsByDay();
    $('#checkbox-container input').each((i, checkbox) => {
      checkbox.addEventListener('change', () => {
        const layerNames = $('#vehicle-select').select2('data').map(option => option.id);
        clearLayers(layers);
        showLayersOnMap(layerNames);
        fitBounds(layerNames);
      });
    });
  }
}

function resetPage() {
  $('#checkbox-container').empty();
  $("#select-container").empty();
  $("#color-select-container").empty();

  forEachLayers(function(layerName) {
    const layerInfos = layers[layerName];
    Object.keys(layerInfos).forEach(key => {
      const layer = layerInfos[key];
      if (map.hasLayer(layer)) {
        map.removeLayer(layer);
      }
    });
  });
}

function getJob(job_id, api_key) {
  resetPage();
  toggleLoading();
  $.ajax({
    type: 'GET',
    url: '/0.1/vrp/jobs/' + job_id + '.json',
    data: {api_key: api_key},
    success: setup,
    error: function(xhr) {
      console.error(xhr);
    },
    complete: toggleLoading
  })
}

function createCheckbox(label, id) {
  const html =
      '<div class="block">' +
      '<input type="checkbox" id="' + id + '"/>' +
      '<label for="' + id + '">' + label + '</label>' +
      '</div>';
  $('#checkbox-container').append(html);
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

function formatVehicleSelect2(state) {
  if (state.loading) {
    return state.text;
  }
  const container = document.createElement('span')
  const dot = document.createElement('span')
  dot.classList.add('dot')
  dot.style = `background-color: ${state.element.dataset.color}`
  const txt = document.createElement('span')
  txt.textContent = ' ' + state.text;
  container.appendChild(dot);
  container.appendChild(txt);
  return container;
}

const layersStore = {};

function hideDay(day) {
  const layerNames = ['points', 'polylines', 'partitionsWorkDay', 'clusters'];
  if (!layersStore[day]) {
    layersStore[day] = [];
  }
  Object.keys(layers).forEach(vehicle => {
    layerNames.forEach(layerName => {
      const mainLayer = layerName === layerNames[3] ? layers[vehicle][layerName] : layers[vehicle][layerName].getLayers()[0];
      mainLayer.eachLayer(layer => {
        if (layer.feature.properties.work_day === day || (layerName === layerNames[1] && (layer.feature.properties.day - 1) % 7 === dayMap.findIndex(d => d === day))) {
          layersStore[day].push({ vehicle: vehicle, layerName: layerName, layer: layer });
          mainLayer.removeLayer(layer);
        }
      });
    });
  });
  refreshClusters();
}

function resetHiddenLayers(day) {
  if (!layersStore[day]) {
    return;
  }
  layersStore[day].forEach(info => {
    if (info.layerName === 'clusters') {
      return layers[info.vehicle][info.layerName].addLayer(info.layer);
    }
    layers[info.vehicle][info.layerName].getLayers()[0].addLayer(info.layer);
  });
  layersStore[day] = [];
}

function formatColorSelect2(state) {
  if (state.loading) {
    return state.text;
  }
  const container = document.createElement('span');
  if (state.text === 'hidden') {
    const icon = document.createElement('i');
    icon.classList.add('far');
    icon.classList.add('fa-eye-slash');
    container.appendChild(icon);
  } else {
    const dot = document.createElement('span')
    dot.classList.add('dot')
    dot.style = state.text === 'default' ? 'border: 1px solid grey;' : `background-color: ${state.text};`;
    container.appendChild(dot);
  }
  if (state.text === 'hidden' || state.text === 'default') {
    container.title = i18next.t('select2_' + state.text + '_title');
  }
  return container;
}

function resetColorForDay(day) {
  Object.keys(layers).forEach(layerName => {
    layers[layerName].partitionsWorkDay.getLayers()[0].eachLayer(layer => {
      if (layer.feature.properties.work_day === day) {
        layer.setStyle({color: layer.feature.properties.color});
        layers[layerName].partitionsWorkDay.removeLayer(layer);
      }
    });
    layers[layerName].points.getLayers()[0].eachLayer(layer => {
      if (layer.feature.properties.work_day === day) {
        layer.setIcon( L.divIcon({html: '<span class="circle" style="background-color: '+ layer.feature.properties.color + ';"/>'}) )
      }
    });
    layers[layerName].polylines.getLayers()[0].eachLayer(layer => {
      if ((layer.feature.properties.day - 1) % 7 === dayMap.findIndex(d => d === day)) {
        layer.setStyle({color: layer.feature.properties.color});
      }
    });
  });
  refreshClusters();
}

function setColorForDay(color, day) {
  Object.keys(layers).forEach(layerName => {
    layers[layerName].partitionsWorkDay.getLayers()[0].eachLayer(layer => {
      if (layer.feature.properties.work_day === day) {
        layer.setStyle({color});
      }
    });
    layers[layerName].points.getLayers()[0].eachLayer(layer => {
      if (layer.feature.properties.work_day === day) {
        layer.setIcon( L.divIcon({html: '<span class="circle" style="background-color: '+ color + ';"/>'}) )
      }
    });
    layers[layerName].polylines.getLayers()[0].eachLayer(layer => {
      if (layer.feature.properties.day % 7 === dayMap.findIndex(d => d === day)) {
        layer.setStyle({color});
      }
    });
  });
}

function refreshClusters() {
  Object.keys(layers).forEach(layerName => {
    if (map.hasLayer(layers[layerName].clusters)) {
      layers[layerName].clusters.refreshClusters();
    }
  });
}

function createColorsSelectsByDay() {
  const colorSelectContainer = document.getElementById('color-select-container');
  dayMap.forEach((day, idx) => {
    if (day !== undefined) {
      const container = document.createElement('div');
      const select = document.getElementById('color-select-template').cloneNode(true);
      const div = document.createElement('div');
      const id = day + '-select';

      div.textContent = day;
      select.id = id;
      container.appendChild(div);
      container.appendChild(select);
      container.classList.add('color-selector');

      if (colorSelectContainer.childNodes.length === 4) {
        colorSelectContainer.appendChild(document.createElement('br'));
      }

      colorSelectContainer.appendChild(container);

      const $select = $('#' + id);
      $select.select2({
        placeholder: i18next.t('select2_placeholder'),
        minimumResultsForSearch: -1,
        width: '90%',
        templateResult: formatColorSelect2,
        templateSelection: formatColorSelect2
      }).on('change.select2', () => {
        const option = $select.select2('data')[0].id;
        if (option === 'hidden' ) {
          return hideDay(day);
        }
        resetHiddenLayers(day);
        if (option === 'default') {
          return resetColorForDay(day);
        }
        setColorForDay(option, day);
        refreshClusters();
      });
    }
  });
}

function createSelect2(vehicleNames, onChange) {
  const select = document.createElement('select');
  select.setAttribute('multiple', '');
  select.id = 'vehicle-select';
  vehicleNames.forEach(name => {
    const option = document.createElement('option')
    option.dataset.color = colorByVehicle[name];
    option.value = name;
    option.text = name === 'unassigned' ? i18next.t('unassigned') : name;
    select.appendChild(option);
  });
  document.getElementById('select-container').appendChild(select);

  const $select = $(`#${select.id}`);
  $select.select2({
    placeholder: i18next.t('select2_placeholder'),
    allowClear: true,
    width: '90%',
    templateResult: formatVehicleSelect2,
    templateSelection: formatVehicleSelect2
  }).on('change.select2', () => {
    onChange($select.select2('data').map(option => option.id));
  });

}

function createVehicle() {
  return { points: [], polylines: [], partitionsWorkDay: [], partitionsVehicle: [] }
}

function parseFeatures(result, features, key) {
  features.forEach(feature => {
    if (feature.properties.vehicle) {
      if (!result[feature.properties.vehicle]) {
        result[feature.properties.vehicle] = createVehicle();
      }
      return result[feature.properties.vehicle][key].push(feature);
    }
    result.unassigned[key].push(feature)
  });
}

function parseGeojson(geojson) {
  const result = {
    unassigned: { points: [], polylines: [], partitionsWorkDay: [], partitionsVehicle: [] },
  };

  if (geojson.points) {
    parseFeatures(result, geojson.points.features, 'points');
    createCheckbox('Points', 'points');
  }
  if (geojson.polylines) {
    parseFeatures(result, geojson.polylines.features, 'polylines');
    createCheckbox('Polylines', 'polylines');
  }
  if (!geojson.partitions) {
    return result;
  }
  if (geojson.partitions.work_day) {
    parseFeatures(result, geojson.partitions.work_day.features, 'partitionsWorkDay');
    createCheckbox('Partitions work day', 'partitionsWorkDay');
  }
  if (geojson.partitions.vehicle) {
    parseFeatures(result, geojson.partitions.vehicle.features, 'partitionsVehicle');
    createCheckbox('Partitions vehicle', 'partitionsVehicle');
  }
  return result;
}

function clearLayers(layers) {
  Object.keys(layers).forEach(layersKey => {
    Object.keys(layers[layersKey]).forEach(layerKey => {
      map.removeLayer(layers[layersKey][layerKey]);
    })
  });
};

function parseVehicleFeatures(features, layer, onEachFeatureCallback) {
  L.geoJSON({ type: "FeatureCollection", features }, {
    onEachFeature: function (feature, layer) {
      if (onEachFeatureCallback) {
        onEachFeatureCallback(feature, layer);
      }
      layer.setStyle({
        color: feature.properties.color
      });
      layer.bindPopup(createPopupContent(feature.properties));
    }
  }).addTo(layer)
}

function vehicleToGeojson(vehicle) {
  const layers = { clusters: new L.markerClusterGroup(), points: new L.featureGroup(), polylines: new L.featureGroup(), partitionsWorkDay: new L.featureGroup(), partitionsVehicle: new L.featureGroup() }

  L.geoJSON({ type: "FeatureCollection", features: vehicle.points }, {
    pointToLayer: function(geoJsonPoint, latlng) {
      const marker = L.marker(latlng, {
        icon: L.divIcon({html: '<span class="circle" style="background-color: '+ geoJsonPoint.properties.color + ';"/>'}),
      });
      marker.bindPopup(createPopupContent(geoJsonPoint.properties));
      return marker;
    }
  }).addTo(layers.points).addTo(layers.clusters);

  parseVehicleFeatures(vehicle.polylines, layers.polylines);
  parseVehicleFeatures(vehicle.partitionsWorkDay, layers.partitionsWorkDay);
  parseVehicleFeatures(vehicle.partitionsVehicle, layers.partitionsVehicle, (feature) => colorByVehicle[feature.properties.vehicle] = feature.properties.color);

  return layers;
}

function parsedGeojsonToLayers(parsedGeojson) {
  const layers = {}
  Object.keys(parsedGeojson).forEach(key => {
    layers[key] = vehicleToGeojson(parsedGeojson[key]);
  });
  return layers;
}
