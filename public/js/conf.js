var getParams = function() {
  var parameters = {};
  var parts = window.location.search.replace(/[?&]+([^=&]+)=?([^&#]*)/gi, function(match, key, value, offset) {
    parameters[key] = value;
  });
  return parameters;
};

var debug = (window.location.search.search('debug') != -1) ? true : false;

var i18n = {
  title: 'Optimisez vos fichiers CSV',
  form: {
    'file-customers-label': 'Votre fichier clients csv :',
    'file-vehicles-label': 'Votre fichier véhicules csv :',
    'optim-options-legend': 'Options de l\'optimisation :',
    'optim-duration-label': 'Durée maximale :',
    'optim-iterations-label': 'Nombre maximum d\'itérations :',
    'optim-iterations-without-improvment-label': 'Itérations sans amélioration (arrêt automatique) :',
    'optim-solver-parameter-label': 'Méthode de résolution :',
    'send-files': 'Envoyer',
    'send-csvs': 'Envoyer',
    'csv-points-label': 'Votre fichier points csv :',
    'csv-units-label': 'Votre fichier units csv :',
    'csv-capacities-label': 'Votre fichier capacities csv :',
    'csv-quantities-label': 'Votre fichier quantities csv :',
    'csv-timewindows-label': 'Votre fichier timewindows csv :',
    'csv-services-label': 'Votre fichier services csv :',
    'csv-shipments-label': 'Votre fichier shipments csv :',
    'csv-vehicles-label': 'Votre fichier vehicules csv :',
    'json-config-label': 'Votre fichier de configuration :',
    'result-label': 'Résultat de votre optimisation :',
    'status-label': 'Status de votre optimisation :',
    'invalidConfig': 'Fichier de configuration absent'
  },
  completed: 'Terminée le',
  failed: 'Echec',
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
  waitingSubmit: 'En attente de l\'envoi du problème',
  optimizeQueued: 'En attente d\'un processus disponible...',
  optimizeLoading: 'Traitement et optimisation en cours...',
  optimizeFinished: 'optimisation terminée',
  optimizeFinishedError: 'optimisation sans résultat',
  failureCallOptim: function(error) {
    return 'Erreur interne en lançant le service d\'optimisation : ' + error;
  },
  failureOptim: function(attempts, error) {
    return 'Impossible de maintenir la connexion avec le service d\'optimisation (' + attempts + ' tentatives) : ' + error;
  },
  currentJobs: 'Vos optimisations',
  unauthorizedError: 'Vous n\'êtes pas autorisé',
  killOptim: 'Arrêter l\'optimisation',
  deleteOptim: 'Supprimer',
  displaySolution: 'Afficher la solution intermédiaire',
  downloadCSV: 'Télécharger le fichier CSV',
  downloadJSON: 'Télécharger le fichier json',
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
  tags: 'libellés',
};

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
