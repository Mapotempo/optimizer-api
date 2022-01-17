'use strict';

$(document).ready(function() {
  var data = {
    customers: [],
    vehicles: []
  };
  var customers = [];
  var timer = null;

  jobsManager.ajaxGetJobs(true);

  $('#optim-list-legend').html(i18next.t('current_jobs'));

  $('#file-customers-help .column-name').append('<td class="required">' + mapping.reference + '</td>');
  $('#file-customers-help .column-value').append('<td class="required">ref</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.pickup_lat + '</td>');
  $('#file-customers-help .column-value').append('<td>0.123</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.pickup_lon + '</td>');
  $('#file-customers-help .column-value').append('<td>0.123</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.pickup_start + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.pickup_end + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.pickup_duration + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.pickup_setup + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.delivery_lat + '</td>');
  $('#file-customers-help .column-value').append('<td>0.123</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.delivery_lon + '</td>');
  $('#file-customers-help .column-value').append('<td>0.123</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.delivery_start + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.delivery_end + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.delivery_duration + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.delivery_setup + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.quantity + ' 1</td>');
  $('#file-customers-help .column-value').append('<td>1.234</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.quantity + ' 2</td>');
  $('#file-customers-help .column-value').append('<td>1.234</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.skills + '</td>');
  $('#file-customers-help .column-value').append('<td>tag1,tag2</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.shipment_inroute + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');

  $('#file-vehicles-help .column-name').append('<td>' + mapping.reference + '</td>');
  $('#file-vehicles-help .column-value').append('<td>ref</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.start_lat + '</td>');
  $('#file-vehicles-help .column-value').append('<td>0.123</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.start_lon + '</td>');
  $('#file-vehicles-help .column-value').append('<td>0.123</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.end_lat + '</td>');
  $('#file-vehicles-help .column-value').append('<td>0.123</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.end_lon + '</td>');
  $('#file-vehicles-help .column-value').append('<td>0.123</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.cost_fixed + '</td>');
  $('#file-vehicles-help .column-value').append('<td>1</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.cost_distance_multiplier + '</td>');
  $('#file-vehicles-help .column-value').append('<td>2</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.cost_time_multiplier + '</td>');
  $('#file-vehicles-help .column-value').append('<td>3</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.cost_waiting_time_multiplier + '</td>');
  $('#file-vehicles-help .column-value').append('<td>4</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.cost_setup_time_multiplier + '</td>');
  $('#file-vehicles-help .column-value').append('<td>5</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.coef_setup + '</td>');
  $('#file-vehicles-help .column-value').append('<td>1.5</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.start_time + '</td>');
  $('#file-vehicles-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.end_time + '</td>');
  $('#file-vehicles-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.route_duration + '</td>');
  $('#file-vehicles-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.quantity + ' 1</td>');
  $('#file-vehicles-help .column-value').append('<td>1.234</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.quantity + ' 2</td>');
  $('#file-vehicles-help .column-value').append('<td>1.234</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.initial_quantity + ' 1</td>');
  $('#file-vehicles-help .column-value').append('<td>1.234</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.initial_quantity + ' 2</td>');
  $('#file-vehicles-help .column-value').append('<td>1.234</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.skills + ' 1</td>');
  $('#file-vehicles-help .column-value').append('<td>tag1,tag2</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.skills + ' 2</td>');
  $('#file-vehicles-help .column-value').append('<td>tag1,tag3</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.router_mode + '</td>');
  $('#file-vehicles-help .column-value').append('<td>car</i></td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.router_dimension + '</td>');
  $('#file-vehicles-help .column-value').append('<td>time | distance <i>(défaut : time)</i></td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.speed_multiplier + '</td>');
  $('#file-vehicles-help .column-value').append('<td>0.9 <i>(défaut : 1.0)</i></td>');

  var filterInt = function(value) {
    if (/^(-|\+)?([0-9]+|Infinity)$/.test(value))
      return Number(value);
    return NaN;
  };
  var duration = function(value) {
    if (!isNaN(filterInt(value)))
      return filterInt(value);
    else if (/[0-9]{1,2}:[0-9]{2}:[0-9]{2}/.test(value)) {
      var t = value.split(':');
      return t[0] * 3600 + t[1] * 60 + Number(t[2]);
    }
    else if (value)
      throw i18next.t('invalid_duration', { duration: value });
  };
  customers = [];

  var buildVRP = function() {
    var correspondant = { 0: 'path_cheapest_arc', 1: 'global_cheapest_arc', 2: 'local_cheapest_insertion', 3: 'savings', 4: 'parallel_cheapest_insertion', 5: 'first_unbound', 6: 'christofides' }
    if (data.customers.length > 0 && data.vehicles.length > 0) {
      if (debug) console.log('Build json from csv: ', data);
      var vrp = {points: [], units: [], shipments: [], services: [], vehicles: [], configuration: {
        preprocessing: {
          cluster_threshold: 0,
          first_solution_strategy: correspondant[parseInt($('#optim-solver-parameter').val())]
        },
        resolution: {
          duration: duration($('#optim-duration').val()) * 1000 || undefined,
          minimum_duration: duration($('#optim-minimum-duration').val() * 1000) || undefined
        }
      }};

      // units
      vrp.units.push({
        id: 'unit0',
        label: 'kg'
      }, {
        id: 'unit1',
        label: 'kg'
      });

      // points
      var points = [];
      data.customers.forEach(function(customer) {
        if (!customer[mapping.reference || 'reference'])
          throw i18next.t('missing_column', { columnName: mapping.reference || 'reference' });
        else if (!customer[mapping.pickup_lat || 'pickup_lat'] && !customer[mapping.pickup_lon || 'pickup_lon'] && !customer[mapping.delivery_lat || 'delivery_lat'] && !customer[mapping.delivery_lon || 'delivery_lon'])
          throw i18next.t('missing_column', { columnName: 'pickup/delivery coordinates' });
        else if (!customer[mapping.pickup_lat || 'pickup_lat'] ^ !customer[mapping.pickup_lon || 'pickup_lon'])
          throw i18next.t('missing_column', { columnName: 'pickup coordinates' });
        else if (!customer[mapping.delivery_lat || 'delivery_lat'] ^ !customer[mapping.delivery_lon || 'delivery_lon'])
          throw i18next.t('missing_column', { columnName: 'delivery coordinates' });

        if (customers.indexOf(customer[mapping.reference || 'reference']) === -1)
          customers.push(customer[mapping.reference || 'reference']);
        else
          throw i18next.t('same_reference', { reference: customer[mapping.reference || 'reference'] });

        if (customer[mapping.pickup_lat || 'pickup_lat'] && customer[mapping.pickup_lon || 'pickup_lon']) {
          var refPickup = customer[mapping.pickup_lat || 'pickup_lat'].replace(',', '.') + ',' + customer[mapping.pickup_lon || 'pickup_lon'].replace(',', '.');
          if (points.indexOf(refPickup) === -1) {
            points.push(refPickup);
            vrp.points.push({
              id: refPickup,
              location: {
                lat: customer[mapping.pickup_lat || 'pickup_lat'].replace(',', '.'),
                lon: customer[mapping.pickup_lon || 'pickup_lon'].replace(',', '.')
              }
            });
          }
        }
      });
      data.customers.forEach(function(customer) {
        if (customer[mapping.delivery_lat || 'delivery_lat'] && customer[mapping.delivery_lon || 'delivery_lon']) {
          var refDelivery = customer[mapping.delivery_lat || 'delivery_lat'].replace(',', '.') + ',' + customer[mapping.delivery_lon || 'delivery_lon'].replace(',', '.');
          if (points.indexOf(refDelivery) === -1) {
            points.push(refDelivery);
            vrp.points.push({
              id: refDelivery,
              location: {
                lat: customer[mapping.delivery_lat || 'delivery_lat'].replace(',', '.'),
                lon: customer[mapping.delivery_lon || 'delivery_lon'].replace(',', '.')
              }
            });
          }
        }
      });
      var router_modes = [];
      var router_dimensions = [];
      var speed_multipliers = [];
      data.vehicles.forEach(function(vehicle) {
        if (router_modes.indexOf(vehicle[mapping.router_mode || 'router_mode']) == -1) router_modes.push(vehicle[mapping.router_mode || 'router_mode']);
        if (router_dimensions.indexOf(vehicle[mapping.router_dimension || 'router_dimension']) == -1) router_dimensions.push(vehicle[mapping.router_dimension || 'router_dimension']);
        if (speed_multipliers.indexOf(vehicle[mapping.speed_multiplier || 'speed_multiplier']) == -1) speed_multipliers.push(vehicle[mapping.speed_multiplier || 'speed_multiplier']);

        if (vehicle[mapping.start_lat || 'start_lat'] && vehicle[mapping.start_lon || 'start_lon']) {
          var refStart = vehicle[mapping.start_lat || 'start_lat'].replace(',', '.') + ',' + vehicle[mapping.start_lon || 'start_lon'].replace(',', '.');
          if (points.indexOf(refStart) === -1) {
            points.push(refStart);
            vrp.points.push({
              id: refStart,
              location: {
                lat: vehicle[mapping.start_lat || 'start_lat'].replace(',', '.'),
                lon: vehicle[mapping.start_lon || 'start_lon'].replace(',', '.')
              }
            });
          }
        }
        if (vehicle[mapping.end_lat || 'end_lat'] && vehicle[mapping.end_lon || 'end_lon']) {
          var refEnd = vehicle[mapping.end_lat || 'end_lat'].replace(',', '.') + ',' + vehicle[mapping.end_lon || 'end_lon'].replace(',', '.');
          if (points.indexOf(refEnd) === -1) {
            points.push(refEnd);
            vrp.points.push({
              id: refEnd,
              location: {
                lat: vehicle[mapping.end_lat || 'end_lat'].replace(',', '.'),
                lon: vehicle[mapping.end_lon || 'end_lon'].replace(',', '.')
              }
            });
          }
        }
      });

      // vehicles
      data.vehicles.forEach(function(vehicle) {
        var quantities = [];
        $.each(vehicle, function(key, val) {
          var regexp = '\\s([0-9]+)$';
          var matches = key.match(new RegExp('^' + (mapping.quantity || 'quantity') + regexp));
          if (matches) quantities[matches[1]] = $.extend(quantities[matches[1]], {limit: val});
          matches = key.match(new RegExp((mapping.initial_quantity || 'initial_quantity') + regexp));
          if (matches) quantities[matches[1]] = $.extend(quantities[matches[1]], {initial: val});
        });
        vrp.vehicles.push({
          id: vehicle[mapping.reference || 'reference'],
          start_point_id: (vehicle[mapping.start_lat || 'start_lat'] && vehicle[mapping.start_lat || 'start_lon']) ? vehicle[mapping.start_lat || 'start_lat'].replace(',', '.') + ',' + vehicle[mapping.start_lon || 'start_lon'].replace(',', '.') : null,
          end_point_id: (vehicle[mapping.end_lat || 'end_lat'] && vehicle[mapping.end_lat || 'end_lon']) ? vehicle[mapping.end_lat || 'end_lat'].replace(',', '.') + ',' + vehicle[mapping.end_lon || 'end_lon'].replace(',', '.') : null,
          cost_fixed: vehicle[mapping.cost_fixed || 'cost_fixed'] && vehicle[mapping.cost_fixed || 'cost_fixed'].replace(',', '.'),
          cost_distance_multiplier: vehicle[mapping.cost_distance_multiplier || 'cost_distance_multiplier'] && vehicle[mapping.cost_distance_multiplier || 'cost_distance_multiplier'].replace(',', '.'),
          cost_time_multiplier: vehicle[mapping.cost_time_multiplier || 'cost_time_multiplier'] && vehicle[mapping.cost_time_multiplier || 'cost_time_multiplier'].replace(',', '.'),
          cost_waiting_time_multiplier: vehicle[mapping.cost_waiting_time_multiplier || 'cost_waiting_time_multiplier'] && vehicle[mapping.cost_waiting_time_multiplier || 'cost_waiting_time_multiplier'].replace(',', '.'),
          cost_setup_time_multiplier: vehicle[mapping.cost_setup_time_multiplier || 'cost_setup_time_multiplier'] && vehicle[mapping.cost_setup_time_multiplier || 'cost_setup_time_multiplier'].replace(',', '.'),
          coef_setup: vehicle[mapping.coef_setup || 'coef_setup'] && vehicle[mapping.coef_setup || 'coef_setup'].replace(',', '.'),
          capacities: $.map(quantities.filter(function(n) {return n != undefined;}), function(val, key) {return $.extend(val, {unit_id: 'unit'+ key});}),
          skills: $.map(vehicle, function(val, key) {
            if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val && Array(val.split(','));
          }).filter(function(el) {
            return el && el.length > 0;
          }),
          timewindow: {
            start: duration(vehicle[mapping.start_time || 'start_time']) || null,
            end: duration(vehicle[mapping.end_time || 'end_time']) || null
          },
          duration: duration(vehicle[mapping.route_duration || 'duration']) || null,
          router_mode: vehicle[mapping.router_mode || 'router_mode'] || 'car',
          router_dimension: vehicle[mapping.router_dimension || 'router_dimension'] || 'time',
          speed_multiplier: (vehicle[mapping.speed_multiplier || 'speed_multiplier'] || '').replace(',', '.') || 1,
        });
      });

      // shipments
      data.customers.forEach(function(customer) {
        if (customer[mapping.pickup_lat || 'pickup_lat'] && customer[mapping.pickup_lon || 'pickup_lon'] && customer[mapping.delivery_lat || 'delivery_lat'] && customer[mapping.delivery_lon || 'delivery_lon']) {
          var quantities = [];
          $.each(customer, function(key, val) {
            var regexp = '\\s([0-9]+)$';
            var matches = key.match(new RegExp((mapping.quantity || 'quantity') + regexp));
            if (matches) quantities[matches[1]] = $.extend(quantities[matches[1]], {value: val});
          });
          vrp.shipments.push({
            id: customer[mapping.reference || 'reference'],
            maximum_inroute_duration: duration(customer[mapping.shipment_inroute || 'shipment_inroute']) || null,
            pickup: {
              point_id: customer[mapping.pickup_lat || 'pickup_lat'].replace(',', '.') + ',' + customer[mapping.pickup_lon || 'pickup_lon'].replace(',', '.'),
              timewindows: [{
                start: duration(customer[mapping.pickup_start || 'pickup_start']) || null,
                end: duration(customer[mapping.pickup_end || 'pickup_end']) || null
              }],
              setup_duration: duration(customer[mapping.pickup_setup || 'pickup_setup']) || null,
              duration: duration(customer[mapping.pickup_duration || 'pickup_duration']) || null
            },
            delivery: {
              point_id: customer[mapping.delivery_lat || 'delivery_lat'].replace(',', '.') + ',' + customer[mapping.delivery_lon || 'delivery_lon'].replace(',', '.'),
              timewindows: [{
                start: duration(customer[mapping.delivery_start || 'delivery_start']) || null,
                end: duration(customer[mapping.delivery_end || 'delivery_end']) || null
              }],
              setup_duration: duration(customer[mapping.delivery_setup || 'delivery_setup']) || null,
              duration: duration(customer[mapping.delivery_duration || 'delivery_duration']) || null
            },
            quantities: $.map(quantities.filter(function(n) {return n != undefined;}), function(val, key) {return $.extend(val, {unit_id: 'unit'+ key});}),
            skills: $.map(customer, function(val, key) {
              if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val;
            }).join(',').split(',').filter(function(el) {
              return el;
            })
          });
          // Service : Pickup
        } else if (customer[mapping.pickup_lat || 'pickup_lat'] && customer[mapping.pickup_lon || 'pickup_lon']) {
          var quantities = [];
          $.each(customer, function(key, val) {
            var regexp = '\\s([0-9]+)$';
            var matches = key.match(new RegExp((mapping.quantity || 'quantity') + regexp));
            if (matches) quantities[matches[1]] = $.extend(quantities[matches[1]], {value: val});
          });
          vrp.services.push({
            id: customer[mapping.reference || 'reference'],
            type: 'pickup',
            activity: {
              point_id: customer[mapping.pickup_lat || 'pickup_lat'].replace(',', '.') + ',' + customer[mapping.pickup_lon || 'pickup_lon'].replace(',', '.'),
              timewindows: [{
                start: duration(customer[mapping.pickup_start || 'pickup_start']) || null,
                end: duration(customer[mapping.pickup_end || 'pickup_end']) || null
              }],
              setup_duration: duration(customer[mapping.pickup_setup || 'pickup_setup']) || null,
              duration: duration(customer[mapping.pickup_duration || 'pickup_duration']) || null
            },
            quantities: $.map(quantities.filter(function(n) {return n != undefined;}), function(val, key) {return $.extend(val, {unit_id: 'unit'+ key});}),
            skills: $.map(customer, function(val, key) {
              if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val;
            }).join(',').split(',').filter(function(el) {
              return el;
            })
          });
          // Service : Delivery
        } else if (customer[mapping.delivery_lat || 'delivery_lat'] && customer[mapping.delivery_lon || 'delivery_lon']) {
          var quantities = [];
          $.each(customer, function(key, val) {
            var regexp = '\\s([0-9]+)$';
            var matches = key.match(new RegExp((mapping.quantity || 'quantity') + regexp));
            if (matches) quantities[matches[1]] = $.extend(quantities[matches[1]], {value: val});
          });
          vrp.services.push({
            id: customer[mapping.reference || 'reference'],
            type: 'delivery',
            activity: {
              point_id: customer[mapping.delivery_lat || 'delivery_lat'].replace(',', '.') + ',' + customer[mapping.delivery_lon || 'delivery_lon'].replace(',', '.'),
              timewindows: [{
                start: duration(customer[mapping.delivery_start || 'delivery_start']) || null,
                end: duration(customer[mapping.delivery_end || 'delivery_end']) || null
              }],
              setup_duration: duration(customer[mapping.delivery_setup || 'delivery_setup']) || null,
              duration: duration(customer[mapping.delivery_duration || 'delivery_duration']) || null
            },
            quantities: $.map(quantities.filter(function(n) {return n != undefined;}), function(val, key) {return $.extend(val, {unit_id: 'unit'+ key});}),
            skills: $.map(customer, function(val, key) {
              if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val;
            }).join(',').split(',').filter(function(el) {
              return el;
            })
          });
        }
      });

      if (vrp.services.length == 0) delete vrp.services;
      if (vrp.shipments.length == 0) delete vrp.shipments;

      return vrp;
    }
  };

  var lastSolution = null;
  var callOptimization = function (vrp, callback) {
    lastSolution = null;
    jobsManager.submit({
      contentType: 'application/json',
      data: JSON.stringify({ vrp: vrp }),
    }).done(function (result) {
      if (debug) console.log("Calling optimization... ", result);
      $('#optim-infos').append(' <input id="optim-job-uid" type="hidden" value="' + result.job.id + '"></input><button id="optim-kill">' + i18next.t('kill_optim') + '</button>');
      timer = displayTimer();
      $('#optim-kill').click(function (e) {
        jobsManager.delete($('#optim-job-uid').val())
        .done(function () {
          $('#optim-infos').html('');
          displayPDSolution(result, { initForm: true });
        })
        e.preventDefault();
        return false;
      });

      var delay = 5000;
      jobsManager.checkJobStatus({
        job: result.job,
        format: '.json',
        interval: delay,
      }, function (err, job) {

        // on job error
        if (err) {
          if (debug) console.log("Error: ", err);
          alert("An error occured");
          initForm();
          clearInterval(timer);
          return;
        }

        $('#avancement').html(job.job.avancement);
        if (job.job.status == 'queued') {
          if ($('#optim-status').html() != i18next.t('optimize_queued')) $('#optim-status').html(i18next.t('optimize_queued'));
        }
        else if (job.job.status == 'working') {
          if ($('#optim-status').html() != i18next.t('optimize_loading')) $('#optim-status').html(i18next.t('optimize_loading'));
          if (job.solutions && job.solutions[0]) {
            if (!lastSolution)
              $('#optim-infos').append(' - <a href="#" id="display-solution">' + i18next.t('display_solution') + '</a>');
            lastSolution = job.solutions[0];
            $('#display-solution').click(function (e) {
              displayPDSolution(job);
              e.preventDefault();
              return false;
            });
          }
          if (job.job.graph) {
            displayGraph(job.job.graph);
          }
          return true;
        }
        else if (job.job.status == 'completed') {
          if (debug) console.log('Job completed: ' + JSON.stringify(job));
          if (job.job.graph) {
            displayGraph(job.job.graph);
          }
          callback(job);
        }
        else if (job.job.status == 'failed' || job.job.status == 'killed') {
          if (debug) console.log('Job failed/killed: ' + JSON.stringify(job));
          alert(i18next.t('failure_call_optim', { error: job.job.avancement}));
          initForm();
          clearInterval(timer);
        }
      })
    }).fail(function (xhr, status, message) {
      alert(i18next.t('failure_call_optim', { error: status + " " + message + " " + xhr.responseText}));
      initForm();
      clearInterval(timer);
    })
  };

  const fieldsName = {
    reference: 'référence',
    route: 'tournée',
    vehicle: 'véhicule',
    stop_type: 'type arrêt',
    name: 'nom',
    street: 'voie',
    postalcode: 'code postal',
    city: 'ville',
    lat: 'lat',
    lng: 'lng',
    take_over: 'durée visite',
    quantity1_1: 'quantité 1_1',
    quantity1_2: 'quantité 1_2',
    open: 'horaire début',
    close: 'horaire fin',
    tags: 'libellés'
  }

  var createCSV = function(solution) {
    var stops = [];
    var i = 0;
    var previous_lat = '';
    var previous_lon = '';
    solution.routes.forEach(function(route) {
      i++;
      route.activities.forEach(function(activity) {
        var setup_duration = activity['detail']['setup_duration'];
        var ref = activity.pickup_shipment_id ? (activity.pickup_shipment_id + ' pickup') : activity.delivery_shipment_id;
        var lat = activity['detail']['lat'];
        var lon = activity['detail']['lon'];
        var start = activity['detail']['timewindows'] && activity['detail']['timewindows'][0] && activity['detail']['timewindows'][0]['start'];
        var d = (previous_lat == lat && previous_lon == lon ? 0 : setup_duration) + (activity['detail']['duration'] || 0);
        var end = activity['detail']['timewindows'] && activity['detail']['timewindows'][0] && activity['detail']['timewindows'][0]['end'];
        var quantity1_1 = activity['detail']['quantities'] && activity['detail']['quantities'].find(function(element) {
          return String(element['unit']) == 'unit0';
        });
        var value1_1 = quantity1_1 && quantity1_1['value'] || 0;
        var quantity1_2 = activity['detail']['quantities'] && activity['detail']['quantities'].find(function(element) {
          return String(element['unit']) == 'unit1';
        });
        var value1_2 = quantity1_2 && quantity1_2['value'] || 0;
        var skills = activity['detail']['skills'] && activity['detail']['skills'].join(',');
        if (activity.pickup_shipment_id || activity.delivery_shipment_id) {
          var customer_id = customers.indexOf(activity.pickup_shipment_id ? activity.pickup_shipment_id : activity.delivery_shipment_id);
          // group only pickup with direct previous pickup on same points
          var lastStop = stops[stops.length - 1];
          if (lastStop && lastStop[0] == ref && activity.pickup_shipment_id) {
            if (d)
              lastStop[10] = lastStop[10] ? (duration(lastStop[10]) + d).toHHMMSS() : d.toHHMMSS();
            if (data.customers[customer_id][mapping.quantity || 'quantity'])
              lastStop[11] = Number(lastStop[11] || 0) + Number(data.customers[customer_id][mapping.quantity || 'quantity'].replace(',', '.') || 0);
            if (duration(start))
              lastStop[12] = lastStop[12] ? (Math.max(duration(lastStop[12]), duration(start)) - d).toHHMMSS() : start;
            if (duration(end))
              lastStop[13] = lastStop[13] ? Math.max(duration(lastStop[13]), duration(end)).toHHMMSS() : end;
            if (skills && skills != lastStop[14])
              lastStop[14] = $.unique(lastStop[14].split(',').concat(skills.split(','))).join(',');
          }
          else {
            stops.push([
              ref,
              i,
              route.vehicle_id,
              'visite',
              ref, // name
              '', // street
              '', // postalcode
              '', // country
              lat,
              lon,
              d ? d.toHHMMSS() : '',
              value1_1,
              value1_2,
              start && start.toHHMMSS(),
              end && end.toHHMMSS(),
              skills
            ]);
          }
          previous_lat = lat;
          previous_lon = lon;
        } else if (activity.service_id) {
          stops.push([
            activity.service_id,
            i,
            route.vehicle_id,
            'visite',
            ref, // name
            '', // street
            '', // postalcode
            '', // country
            lat,
            lon,
            d ? d.toHHMMSS() : '',
            value1_1,
            value1_2,
            start,
            end,
            skills
          ]);
          previous_lat = lat;
          previous_lon = lon;
        } else if (activity.rest_id) {
          stops.push([
            '',
            i,
            route.vehicle_id,
            'pause',
            '',
            '',
            '',
            '',
            '', // lat
            '', // lon
            (activity.end_time - activity.arrival_time).toHHMMSS(),
            '',
            '',
            '', // start
            '', // end
            '',
          ]);
        } else {
          stops.push([
            '',
            i,
            route.vehicle_id,
            'dépôt',
            '', // name
            '', // street
            '', // postalcode
            '', // country
            '',
            '',
            '',
            '',
            '',
            '',
            '',
            '',
          ]);
        }
      });
    });
    solution.unassigned.forEach(function(job) {
      var quantity1_1 = job['detail']['quantities'].find(function(element) {
        return element['unit'] == 'unit0';
      });
      var value1_1 = quantity1_1 && quantity1_1['value'] || 0;
      var quantity1_2 = job['detail']['quantities'].find(function(element) {
        return element['unit'] == 'unit1';
      });
      var value1_2 = quantity1_2 && quantity1_2['value'] || 0;
      if (job.shipment_id) {
        var customer_id = customers.indexOf(job.shipment_id);
        if (job.type == 'delivery') {
          stops.push([
            job.shipment_id,
            '',
            '',
            'visite',
            job.shipment_id, // name
            '', // street
            '', // postalcode
            '', // country
            data.customers[customer_id][mapping.delivery_lat || 'delivery_lat'],
            data.customers[customer_id][mapping.delivery_lon || 'delivery_lon'],
            data.customers[customer_id][mapping.delivery_duration || 'delivery_duration'],
            value1_1,
            value1_2,
            data.customers[customer_id][mapping.delivery_start || 'delivery_start'],
            data.customers[customer_id][mapping.delivery_end || 'delivery_end'],
            $.map(data.customers[customer_id], function(val, key) {
              if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val;
            }).filter(function(el) {
              return el;
            }).join(',')
          ]);
        } else {
          stops.push([
            (job.shipment_id + ' pickup'),
            '',
            '',
            'visite',
            job.shipment_id + ' pickup', // name
            '', // street
            '', // postalcode
            '', // country
            data.customers[customer_id][mapping.pickup_lat || 'pickup_lat'],
            data.customers[customer_id][mapping.pickup_lon || 'pickup_lon'],
            data.customers[customer_id][mapping.pickup_duration || 'pickup_duration'],
            value1_1,
            value1_2,
            data.customers[customer_id][mapping.pickup_start || 'pickup_start'],
            data.customers[customer_id][mapping.pickup_end || 'pickup_end'],
            $.map(data.customers[customer_id], function(val, key) {
              if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val;
            }).filter(function(el) {
              return el;
            }).join(',')
          ]);
        }
      } else {
        var customer_id = customers.indexOf(job.service_id);
        if (data.customers[customer_id][mapping.pickup_lat || 'pickup_lat']) {
          stops.push([
            job.service_id,
            '',
            '',
            'visite',
            job.service_id, // name
            '', // street
            '', // postalcode
            '', // country
            data.customers[customer_id][mapping.pickup_lat || 'pickup_lat'],
            data.customers[customer_id][mapping.pickup_lon || 'pickup_lon'],
            data.customers[customer_id][mapping.pickup_duration || 'pickup_duration'],
            value1_1,
            value1_2,
            data.customers[customer_id][mapping.pickup_start || 'pickup_start'],
            data.customers[customer_id][mapping.pickup_end || 'pickup_end'],
            $.map(data.customers[customer_id], function(val, key) {
              if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val;
            }).filter(function(el) {
              return el;
            }).join(',')
          ]);
        } else if (data.customers[customer_id][mapping.delivery_lat || 'delivery_lat']) { // delivery
          stops.push([
            job.service_id,
            '',
            '',
            'visite',
            job.service_id, // name
            '', // street
            '', // postalcode
            '', // country
            data.customers[customer_id][mapping.delivery_lat || 'delivery_lat'],
            data.customers[customer_id][mapping.delivery_lon || 'delivery_lon'],
            data.customers[customer_id][mapping.delivery_duration || 'delivery_duration'],
            value1_1,
            value1_2,
            data.customers[customer_id][mapping.delivery_start || 'delivery_start'],
            data.customers[customer_id][mapping.delivery_end || 'delivery_end'],
            $.map(data.customers[customer_id], function(val, key) {
              if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val;
            }).filter(function(el) {
              return el;
            }).join(',')
          ]);
        }
      }
    });
    return Papa.unparse({
      fields: [
        fieldsName.reference,
        fieldsName.route,
        fieldsName.vehicle,
        fieldsName.stop_type,
        fieldsName.name,
        fieldsName.street,
        fieldsName.postalcode,
        fieldsName.city,
        fieldsName.lat,
        fieldsName.lng,
        fieldsName.take_over,
        fieldsName.quantity1_1,
        fieldsName.quantity1_2,
        fieldsName.open,
        fieldsName.close,
        fieldsName.tags,
      ],
      data: stops
    });
  };

  var displayPDSolution = function(result, options) {
    var solution = result.solutions[0];
    $('#optim-infos').html('iterations: ' + solution.iterations + ' cost: <b>' + Math.round(solution.cost) + '</b> (time: ' + (solution.total_time && solution.total_time.toHHMMSS()) + ' distance: ' + Math.round(solution.total_distance / 1000) + ')');
    // if (result) {
    var csv = createCSV(solution);
    var jsonData = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(solution));
    $('#optim-infos').append(' - <a download="result_' + result.job.id + '.json" href="' + jsonData + '">' + i18next.t('download_json') + '</a>');
    $('#optim-infos').append(' - <a href="data:text/csv,' + encodeURIComponent(csv) + '">' + i18next.t('download_csv') + '</a>');
    $('#result').html(csv);
    // }
    clearInterval(timer);
    if (options && options.initForm) {
      initForm();
    }
  };

  var configParse = {
    delimiter: "", // auto-detect
    newline: "", // auto-detect
    header: true,
    skipEmptyLines: true,
    error: function(err, file, inputElem, reason)
    {
      alert(i18next.t('error_file', { filename: i18next.t(inputElem.id.replace('file-', '')) }) + reason)
      initForm();
      clearInterval(timer);
      $('#send-files').attr('disabled', false);
    },
    complete: function(res, file, inputElem) {
      if (debug) console.log("Parsing complete: ", res, file);
      data[inputElem.id.replace('file-', '')] = res.data;
      try {
        var vrp = buildVRP();
        if (vrp) {
          if (debug) { console.log("Input json for optim: ", vrp); console.log(JSON.stringify(vrp)); }
          callOptimization(vrp, function(result) {
            displayPDSolution(result)
          });
        }
      }
      catch(e) {
        if (debug) throw e;
        else {
          alert(e);
          initForm();
          clearInterval(timer);
        }
      }
    }
  };

  var beforeFn = function(file, inputElem) {
    if (debug) console.log("Parsing file: ", file);
    data[inputElem.id.replace('file-', '')] = [];
  };

  $('#send-files').click(function(e) {
    var filesCustomers = $('#file-customers')[0].files;
    var filesVehicles = $('#file-vehicles')[0].files;
    if (filesCustomers.length == 1 && filesVehicles.length == 1) {
      $('#send-files').attr('disabled', true);
      $('#optim-infos').html('<span id="optim-status">' + i18next.t('optimize_loading') + '</span> <span id="avancement"></span> - <span id="timer"></span>');
      $('#infos').html('');
      $('#result').html('');
      $('#result-graph').hide();
      $('#file-customers').parse({
        config: configParse,
        before: beforeFn
      });
      $('#file-vehicles').parse({
        config: configParse,
        before: beforeFn
      });
    }
    else {
      alert(i18next.t('missing_file'));
    }
    e.preventDefault();
    return false;
  });
});
