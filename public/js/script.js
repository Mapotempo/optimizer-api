'use_strict';

Number.prototype.toHHMMSS = function () {
  var sec_num = parseInt(this, 10); // don't forget the second param
  var hours   = Math.floor(sec_num / 3600);
  var minutes = Math.floor((sec_num - (hours * 3600)) / 60);
  var seconds = sec_num - (hours * 3600) - (minutes * 60);

  if (hours   < 10) {hours   = "0"+hours;}
  if (minutes < 10) {minutes = "0"+minutes;}
  if (seconds < 10) {seconds = "0"+seconds;}
  return hours+':'+minutes+':'+seconds;
}

$(document).ready(function() {
  var debug = (window.location.search.search('debug') != -1) ? true : false;
  var data = {
    customers: [],
    vehicles: []
  };
  var customers = [];

  var i18n = {
    title: 'Optimisez vos fichiers CSV',
    form: {
      'api-key-label': 'Votre clé d\'api :',
      'file-customers-label': 'Votre fichier clients csv :',
      'file-vehicles-label': 'Votre fichier véhicules csv :',
      'optim-options-legend': 'Options de l\'optimisation :',
      'optim-duration-label': 'Durée maximale :',
      'optim-iterations-label': 'Nombre maximum d\'itérations :',
      'optim-iterations-without-improvment-label': 'Itérations sans amélioration (arrêt automatique) :',
      'send-files': 'Envoyer',
      'result-label': 'Résultat de votre optimisation :'
    },
    customers: 'clients',
    vehicles: 'véhicules',
    missingFile: 'Veuillez renseigner un fichier clients et un fichier véhicles.',
    missingColumn: function(columnName) {
      return 'Colonne manquante ou donnée nulle : ' + columnName;
    },
    sameReference: function(value) {
      return 'Référence identique détectée : ' + value;
    },
    invalidDuration: function(value) {
      return 'Durée invalide : ' + value;
    },
    invalidRouterMode: function(value) {
      return 'Mode de calcul d\'itinéraire non autorisé : ' + value;
    },
    notSameRouter: function(values) {
      return 'Valeurs distinctes non autorisées pour vos véhicules : ' + values.join(', ');
    },
    errorFile: function(filename) {
      return 'Une erreur est survenue en lisant le fichier ' + filename + ': ';
    },
    optimizeQueued: 'En attente d\'un processus disponible...',
    optimizeLoading: 'Traitement et optimisation en cours...',
    failureCallOptim: function(error) {
      return 'Erreur interne en lançant le service d\'optimisation : ' + error;
    },
    failureOptim: function(attempts, error) {
      return 'Impossible de maintenir la connexion avec le service d\'optimisation (' + attempts + ' tentatives) : ' + error;
    },
    killOptim: 'Arrêter l\'optimisation',
    displaySolution: 'Afficher la solution intermédiaire',
    downloadCSV: 'Télécharger le fichier CSV',
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
    quantity: 'quantité',
    open: 'horaire début',
    close: 'horaire fin',
    tags: 'libellés',
  };
  $('head title').html(i18n.title);
  for (id in i18n.form) {
    $('#' + id).html(i18n.form[id]);
  }

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
    quantity: 'quantity 1', // TODO: gérer les quantités multiples
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

  $('#file-customers-help .column-name').append('<td class="required">' + mapping.reference + '</td>');
  $('#file-customers-help .column-value').append('<td class="required">ref</td>');
  $('#file-customers-help .column-name').append('<td class="required">' + mapping.pickup_lat + '</td>');
  $('#file-customers-help .column-value').append('<td class="required">0.123</td>');
  $('#file-customers-help .column-name').append('<td class="required">' + mapping.pickup_lon + '</td>');
  $('#file-customers-help .column-value').append('<td class="required">0.123</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.pickup_start + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.pickup_end + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.pickup_duration + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.pickup_setup + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td class="required">' + mapping.delivery_lat + '</td>');
  $('#file-customers-help .column-value').append('<td class="required">0.123</td>');
  $('#file-customers-help .column-name').append('<td class="required">' + mapping.delivery_lon + '</td>');
  $('#file-customers-help .column-value').append('<td class="required">0.123</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.delivery_start + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.delivery_end + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.delivery_duration + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.delivery_setup + '</td>');
  $('#file-customers-help .column-value').append('<td>HH:MM:SS</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.quantity + '</td>');
  $('#file-customers-help .column-value').append('<td>1.234</td>');
  $('#file-customers-help .column-name').append('<td>' + mapping.skills + '</td>');
  $('#file-customers-help .column-value').append('<td>"tag1,tag2"</td>');

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
  $('#file-vehicles-help .column-name').append('<td>' + mapping.quantity + '</td>');
  $('#file-vehicles-help .column-value').append('<td>1.234</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.skills + ' 1</td>');
  $('#file-vehicles-help .column-value').append('<td>"tag1,tag2"</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.skills + ' 2</td>');
  $('#file-vehicles-help .column-value').append('<td>"tag1,tag3"</td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.router_mode + '</td>');
  $('#file-vehicles-help .column-value').append('<td>car</i></td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.router_dimension + '</td>');
  $('#file-vehicles-help .column-value').append('<td>time | distance <i>(défaut : time)</i></td>');
  $('#file-vehicles-help .column-name').append('<td>' + mapping.speed_multiplier + '</td>');
  $('#file-vehicles-help .column-value').append('<td>0.9 <i>(défaut : 1.0)</i></td>');

  var filterInt = function(value) {
    if (/^(\-|\+)?([0-9]+|Infinity)$/.test(value))
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
      throw i18n.invalidDuration(value);
  };

  var initForm = function() {
    clearInterval(window.optimInterval);
    $('#send-files').attr('disabled', false);
    $('#optim-infos').html('');
  };

  var buildVRP = function() {
    if (data.customers.length > 0 && data.vehicles.length > 0) {
      if (debug) console.log('Build json from csv: ', data);
      var vrp = {points: [], shipments: [], vehicles: [], configuration: {
        preprocessing: {
          cluster_threshold: 0
        },
        resolution: {
          duration: duration($('#optim-duration').val()) * 1000 || 1000,
          iterations: parseInt($('#optim-iterations').val()) || undefined,
          iterations_without_improvment: parseInt($('#optim-iterations-without-improvment').val()) || undefined
        }
      }};

      // points
      var points = []; customers = [];
      data.customers.forEach(function(customer) {
        if (!customer[mapping.reference || 'reference'])
          throw i18n.missingColumn(mapping.reference || 'reference');
        else if (!customer[mapping.pickup_lat || 'pickup_lat'])
          throw i18n.missingColumn(mapping.pickup_lat || 'pickup_lat');
        else if (!customer[mapping.pickup_lon || 'pickup_lon'])
          throw i18n.missingColumn(mapping.pickup_lon || 'pickup_lon');
        else if (!customer[mapping.delivery_lat || 'delivery_lat'])
          throw i18n.missingColumn(mapping.delivery_lat || 'delivery_lat');
        else if (!customer[mapping.delivery_lon || 'delivery_lon'])
          throw i18n.missingColumn(mapping.delivery_lon || 'delivery_lon');

        if (customers.indexOf(customer[mapping.reference || 'reference']) === -1)
          customers.push(customer[mapping.reference || 'reference']);
        else
          throw i18n.sameReference(customer[mapping.reference || 'reference']);

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
      });
      data.customers.forEach(function(customer) {
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
      });
      var router_modes = [];
      var router_dimensions = [];
      var speed_multipliers = [];
      data.vehicles.forEach(function(vehicle) {
        if (vehicle[mapping.router_mode || 'router_mode'] && vehicle[mapping.router_mode || 'router_mode'] != 'car' && vehicle[mapping.router_mode || 'router_mode'] != 'truck')
          throw i18n.invalidRouterMode(vehicle[mapping.router_mode || 'router_mode']);
        if (router_modes.indexOf(vehicle[mapping.router_mode || 'router_mode']) == -1) router_modes.push(vehicle[mapping.router_mode || 'router_mode']);
        if (router_modes.length > 1)
          throw i18n.notSameRouter(router_modes);
        if (router_dimensions.indexOf(vehicle[mapping.router_dimension || 'router_dimension']) == -1) router_dimensions.push(vehicle[mapping.router_dimension || 'router_dimension']);
        if (router_dimensions.length > 1)
          throw i18n.notSameRouter(router_dimensions);
        if (speed_multipliers.indexOf(vehicle[mapping.speed_multiplier || 'speed_multiplier']) == -1) speed_multipliers.push(vehicle[mapping.speed_multiplier || 'speed_multiplier']);
        if (speed_multipliers.length > 1)
          throw i18n.notSameRouter(speed_multipliers);

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

      // shipments
      data.customers.forEach(function(customer) {
        vrp.shipments.push({
          id: customer[mapping.reference || 'reference'],
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
          // TODO: gérer les quantités multiples
          quantities: [{
            id: 'unit',
            values: [(customer[mapping.quantity || 'quantity'] || '').replace(',', '.')]
          }],
          skills: $.map(customer, function(val, key) {
            if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val;
          }).join(',').split(',').filter(function(el) {
            return el;
          })
        });
      });
      data.vehicles.forEach(function(vehicle) {
        vrp.vehicles.push({
          id: vehicle[mapping.reference || 'reference'],
          start_point_id: (vehicle[mapping.start_lat || 'start_lat'] && vehicle[mapping.start_lat || 'start_lon']) ? vehicle[mapping.start_lat || 'start_lat'].replace(',', '.') + ',' + vehicle[mapping.start_lon || 'start_lon'].replace(',', '.') : null,
          end_point_id: (vehicle[mapping.end_lat || 'end_lat'] && vehicle[mapping.end_lat || 'end_lon']) ? vehicle[mapping.end_lat || 'end_lat'].replace(',', '.') + ',' + vehicle[mapping.end_lon || 'end_lon'].replace(',', '.') : null,
          cost_fixed: vehicle[mapping.cost_fixed || 'cost_fixed'],
          cost_distance_multiplier: vehicle[mapping.cost_distance_multiplier || 'cost_distance_multiplier'],
          cost_time_multiplier: vehicle[mapping.cost_time_multiplier || 'cost_time_multiplier'],
          cost_waiting_time_multiplier: vehicle[mapping.cost_waiting_time_multiplier || 'cost_waiting_time_multiplier'],
          cost_setup_time_multiplier: vehicle[mapping.cost_setup_time_multiplier || 'cost_setup_time_multiplier'],
          coef_setup: vehicle[mapping.coef_setup || 'coef_setup'],
          // TODO: gérer les quantités multiples
          quantities: [{
            id: 'unit',
            values: [(vehicle[mapping.quantity || 'quantity'] || '').replace(',', '.')]
          }],
          skills: $.map(vehicle, function(val, key) {
            if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val && Array(val.split(','));
          }).filter(function(el) {
            return el && el.length > 0;
          }),
          timewindows: [{
            start: duration(vehicle[mapping.start_time || 'start_time']) || null,
            end: duration(vehicle[mapping.end_time || 'end_time']) || null
          }],
          duration: duration(vehicle[mapping.route_duration || 'duration']) || null,
          router_mode: vehicle[mapping.router_mode || 'router_mode'] || 'car',
          router_dimension: vehicle[mapping.router_dimension || 'router_dimension'] || 'time',
          speed_multiplier: (vehicle[mapping.speed_multiplier || 'speed_multiplier'] || '').replace(',', '.') || 1,
        });
      });
      return vrp;
    }
  };

  var displayGraph = function(data) {
    $('#result-graph').show();
    var values = data ? $.map(data, function(v, k) { return {x: v.iteration, y: v.cost}; }) : [];
    if (values && values.length > 0) {
      var ctx = document.getElementById('result-graph').getContext('2d');
      new Chart(ctx).Scatter([{
        label: 'Iterations/Cost',
        data: values
      }], {
        bezierCurve: false
      });
    }
  };

  var lastSolution = null;
  var callOptimization = function(vrp, callback) {
    lastSolution = null;
    $.ajax({
      type: 'post',
      contentType: 'application/json',
      data: JSON.stringify({vrp: vrp}),
      url: '/0.1/vrp/submit.json?api_key=' + $('#api-key').val(),
      success: function(result) {
        if (debug) console.log("Calling optimization... ", result);
        var delay = 2000;
        var interval = undefined;
        var nbInterval = 0;
        var nbError = 0;
        var checkResponse = function() {
          if (!interval) {
            $('#optim-infos').append(' <input id="optim-job-uid" type="hidden" value="' + result.job.id + '"></input><button id="optim-kill">' + i18n.killOptim + '</button>');
            $('#optim-kill').click(function(e) {
              $.ajax({
                type: 'delete',
                url: '/0.1/vrp/job/' + $('#optim-job-uid').val() + '.json?api_key=' + $('#api-key').val()
              }).done(function(result) {
                clearInterval(window.optimInterval);
                $('#optim-infos').html('');
                if (lastSolution) {
                  displaySolution(lastSolution, {initForm: true});
                }
              }).fail(function(jqXHR, textStatus) {
                alert(textStatus);
              });
              e.preventDefault();
              return false;
            });
          }
          clearInterval(interval);
          if (delay) {
            $.ajax({
              type: 'get',
              contentType: 'application/json',
              url: '/0.1/vrp/job/' + result.job.id + '.json?api_key=' + $('#api-key').val(),
              success: function(job) {
                nbError = 0;
                $('#avancement').html(job.job.avancement);
                if (job.job.status == 'queued') {
                  if ($('#optim-status').html() != i18n.optimizeQueued) $('#optim-status').html(i18n.optimizeQueued);
                }
                else if (job.job.status == 'working') {
                  if ($('#optim-status').html() != i18n.optimizeLoading) $('#optim-status').html(i18n.optimizeLoading);
                  if (job.solutions && job.solutions[0]) {
                    if (!lastSolution)
                      $('#optim-infos').append(' - <a href="#" id="display-solution">' + i18n.displaySolution + '</a>');
                    lastSolution = job.solutions[0];
                    $('#display-solution').click(function(e) {
                      displaySolution(lastSolution);
                      e.preventDefault();
                      return false;
                    });
                  }
                  if (job.job.graph) {
                    displayGraph(job.job.graph);
                  }
                }
                else if (job.job.status == 'completed') {
                  delay = 0;
                  if (debug) console.log('Job completed: ' + JSON.stringify(job));
                  if (job.job.graph) {
                    displayGraph(job.job.graph);
                  }
                  callback(job.solutions[0]);
                }
                else if (job.job.status == 'failed' || job.job.status == 'killed') {
                  delay = 0;
                  if (debug) console.log('Job failed/killed: ' + JSON.stringify(job));
                  alert(i18n.failureCallOptim(job.job.avancement));
                  initForm();
                }
              },
              error: function(xhr, status) {
                nbError++;
                if (nbError > 2) {
                  delay = 0;
                  alert(i18n.failureOptim(nbError, status));
                  initForm();
                }
              }
            });
            nbInterval++;
            interval = setTimeout(checkResponse, Math.min(delay * nbInterval, 30000));
          }
        }
        checkResponse();
      },
      error: function(xhr, status, message) {
        alert(i18n.failureCallOptim(status + " " + message + " " + xhr.responseText));
        initForm();
      }
    });
  };

  var createCSV = function(solution) {
    var stops = [];
    var i = 0;
    solution.routes.forEach(function(route) {
      i++;
      route.activities.forEach(function(activity) {
        if (activity.pickup_shipment_id || activity.delivery_shipment_id) {
          var customer_id = customers.indexOf(activity.pickup_shipment_id ? activity.pickup_shipment_id : activity.delivery_shipment_id);
          var ref = activity.pickup_shipment_id ? (activity.pickup_shipment_id + ' pickup') : activity.delivery_shipment_id;
          var lat = activity.pickup_shipment_id ? data.customers[customer_id][mapping.pickup_lat || 'pickup_lat'] : data.customers[customer_id][mapping.delivery_lat || 'delivery_lat'];
          var lon = activity.pickup_shipment_id ? data.customers[customer_id][mapping.pickup_lon || 'pickup_lon'] : data.customers[customer_id][mapping.delivery_lon || 'delivery_lon'];
          var d = (activity.ready_time - activity.arrival_time + (duration(activity.pickup_shipment_id ? data.customers[customer_id][mapping.pickup_duration || 'pickup_duration'] : data.customers[customer_id][mapping.delivery_duration || 'delivery_duration']) || 0));
          var start = activity.pickup_shipment_id ? data.customers[customer_id][mapping.pickup_start || 'pickup_start'] : data.customers[customer_id][mapping.delivery_start || 'delivery_start'];
          var end = activity.pickup_shipment_id ? data.customers[customer_id][mapping.pickup_end || 'pickup_end'] : data.customers[customer_id][mapping.delivery_end || 'delivery_end'];
          var skills = $.map(data.customers[customer_id], function(val, key) {
            if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val;
          }).filter(function(el) {
            return el;
          }).join(',');
          // group only pickup with direct previous pickup on same points
          var lastStop = stops[stops.length - 1];
          if (lastStop && lastStop[0] == ref && activity.pickup_shipment_id) {
            if (d)
              lastStop[10] = lastStop[10] ? (duration(lastStop[10]) + d).toHHMMSS() : d.toHHMMSS();
            if (data.customers[customer_id][mapping.quantity || 'quantity'])
              lastStop[11] = Number(lastStop[11] || 0) + Number(data.customers[customer_id][mapping.quantity || 'quantity'].replace(',', '.') || 0);
            if (duration(start))
              lastStop[12] = lastStop[12] ? (Math.max(duration(lastStop[12]), duration(start)) - (activity.ready_time - activity.arrival_time)).toHHMMSS() : start;
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
              data.customers[customer_id][mapping.quantity || 'quantity'].replace(',', '.'), // TODO: gérer les quantités multiples
              start,
              end,
              skills
            ]);
          }
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
            (activity.ready_time - activity.arrival_time).toHHMMSS(),
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
          ]);
        }
      });
    });
    solution.unassigned.forEach(function(job) {
      var customer_id = customers.indexOf(job.shipment_id);
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
        data.customers[customer_id][mapping.quantity || 'quantity'], // TODO: gérer les quantités multiples
        data.customers[customer_id][mapping.delivery_start || 'delivery_start'],
        data.customers[customer_id][mapping.delivery_end || 'delivery_end'],
        $.map(data.customers[customer_id], function(val, key) {
          if (key.replace(/ [0-9]+$/, '') == (mapping.skills || 'skills')) return val;
        }).filter(function(el) {
          return el;
        }).join(',')
      ]);
    });
    return Papa.unparse({
      fields: [
        i18n.reference,
        i18n.route,
        i18n.vehicle,
        i18n.stop_type,
        i18n.name,
        i18n.street,
        i18n.postalcode,
        i18n.city,
        i18n.lat,
        i18n.lng,
        i18n.take_over,
        i18n.quantity,
        i18n.open,
        i18n.close,
        i18n.tags,
      ],
      data: stops
    });
  };

  var displaySolution = function(solution, options) {
    $('#infos').html('iterations: ' + solution.iterations + ' cost: <b>' + Math.round(solution.cost) + '</b> (time: ' + (solution.total_time && solution.total_time.toHHMMSS()) + ' distance: '+ Math.round(solution.total_distance / 1000) + ')');
    // if (result) {
      csv = createCSV(solution);
      $('#infos').append(' - <a href="data:text/csv,' + encodeURIComponent(csv) + '">' + i18n.downloadCSV + '</a>');
      $('#result').html(csv);
    // }
    if (options && options.initForm)
      initForm();
  };

  var configParse = {
    delimiter: "",  // auto-detect
    newline: "",  // auto-detect
    header: true,
    skipEmptyLines: true,
    error: function(err, file, inputElem, reason)
    {
      alert(i18n.errorFile(i18n[inputElem.id.replace('file-', '')]) + reason);
      initForm();
      $('#send-files').attr('disabled', false);
    },
    complete: function(res, file, inputElem) {
      if (debug) console.log("Parsing complete: ", res, file);
      data[inputElem.id.replace('file-', '')] = res.data;
      try {
        var vrp = buildVRP();
        if (vrp) {
          if (debug) { console.log("Input json for optim: ", vrp); console.log(JSON.stringify(vrp)); }
          callOptimization(vrp, function(solution) {
            displaySolution(solution, {initForm: true})
          });
        }
      }
      catch(e) {
        if (debug) throw e;
        else {
          alert(e);
          initForm();
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
      $('#optim-infos').html('<span id="optim-status">' + i18n.optimizeLoading + '</span> <span id="avancement"></span> - <span id="timer"></span>');
      var start = new Date();
      var displayTimer = function() {
        $('#timer').html(((new Date() - start) / 1000).toHHMMSS());
      };
      displayTimer();
      window.optimInterval = setInterval(displayTimer, 1000);
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
      alert(i18n.missingFile);
    }
    e.preventDefault();
    return false;
  });
});
