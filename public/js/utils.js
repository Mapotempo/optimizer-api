
Number.prototype.toHHMMSS = function() {
  var sec_num = parseInt(this, 10); // don't forget the second param
  var hours   = Math.floor(sec_num / 3600);
  var minutes = Math.floor((sec_num - (hours * 3600)) / 60);
  var seconds = sec_num - (hours * 3600) - (minutes * 60);

  if (hours   < 10) {hours   = "0"+hours;}
  if (minutes < 10) {minutes = "0"+minutes;}
  if (seconds < 10) {seconds = "0"+seconds;}
  return hours+':'+minutes+':'+seconds;
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

var displayTimer = function() {
  var start = new Date();
  return setInterval(function() {
    $('#timer').html(((new Date() - start) / 1000).toHHMMSS());
  }, 1000);
};
