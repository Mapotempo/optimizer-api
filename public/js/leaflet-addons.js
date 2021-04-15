function initializeLeafletOptions() {
  window.leafletOptions = {
    showClusters: true
  }
}

L.Control.ClustersControl = L.Control.extend({
  onAdd: function(map) {
    const container = L.DomUtil.create('div', 'leaflet-bar leaflet-control leaflet-control-disable-clusters');
    container.style.backgroundColor = 'white';
    container.style.width = '26px';
    container.style.height = '26px';

    const button = L.DomUtil.create('a', '', container);
    const buttonTitleEnabled = 'Désactiver les clusters';
    const buttonTitleDisabled = 'Activer les clusters';

    let icon;

    if (window.leafletOptions.showClusters === true) {
      icon = L.DomUtil.create('i', 'cluster-icon fa fa-certificate fa-lg', button);
      button.title = buttonTitleDisabled;
    } else {
      icon = L.DomUtil.create('i', 'cluster-icon fa fa-certificate fa-circle-o fa-lg', button);
      button.title = buttonTitleEnabled;
    }

    icon.style.marginLeft = '2px';
    const that = this;
    container.onclick = function(e) {
      e.stopPropagation();
      window.leafletOptions.showClusters = !window.leafletOptions.showClusters;
      if (typeof that.options.onSwitch === 'function') {
        that.options.onSwitch();
      }
      $('.cluster-icon').toggleClass('fa-circle-o');
      button.title = $('.cluster-icon').hasClass('fa-circle-o') ? buttonTitleEnabled : buttonTitleDisabled;
    };

    return container;
  }
});

L.Control.clustersControl = function(options) {
  return new L.Control.ClustersControl(options);
}

initializeLeafletOptions();
