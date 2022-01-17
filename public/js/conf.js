var getParams = function() {
  var parameters = {};
  var parts = window.location.search.replace(/[?&]+([^=&]+)=?([^&#]*)/gi, function(match, key, value, offset) {
    parameters[key] = value;
  });
  return parameters;
};

var debug = (window.location.search.search('debug') != -1) ? true : false;

var mapping = {
  reference: 'reference',
  pickup_lat: 'pickup_lat',
  pickup_lon: 'pickup_lng',
  pickup_start: 'pickup_start',
  pickup_end: 'pickup_end',
  pickup_duration: 'pickup_duration',
  pickup_setup: 'pickup_setup',
  delivery_lat: 'delivery_lat',
  delivery_lon: 'delivery_lng',
  delivery_start: 'delivery_start',
  delivery_end: 'delivery_end',
  delivery_duration: 'delivery_duration',
  delivery_setup: 'delivery_setup',
  skills: 'skills',
  quantity: 'quantity',
  shipment_inroute: 'maximum_inroute_duration',
  initial_quantity: 'initial quantity',
  start_lat: 'start_lat',
  start_lon: 'start_lng',
  end_lat: 'end_lat',
  end_lon: 'end_lng',
  cost_fixed: 'fix_cost',
  cost_distance_multiplier: 'distance_cost',
  cost_time_multiplier: 'time_cost',
  cost_waiting_time_multiplier: 'wait_cost',
  cost_late_multiplier: '',
  cost_setup_time_multiplier: 'setup_cost',
  coef_setup: 'setup_multiplier',
  start_time: 'start_time',
  end_time: 'end_time',
  route_duration: 'duration',
  speed_multiplier: 'speed_multiplier',
  router_mode: 'router_mode',
  router_dimension: 'router_dimension'
};
