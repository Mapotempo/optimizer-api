
var jsonFile = null;
var jsonFileDOM = $('#json-file');
var postForm = $('#post-form');
var timer = null;

jobsManager.ajaxGetJobs(true);

jsonFileDOM.on('change', function (e) {
  jsonFile = e.target.files[0]
});

postForm.on('submit', function (e) {
  e.preventDefault();
  var file = jsonFile || jsonFileDOM.files && jsonFileDOM.files[0];
  if (!file) {
    alert("Vous devez d'abord selectionner un fichier");
    return false;
  }

  var reader = new FileReader();
  reader.onload = function (evt) {
    var vrp = JSON.parse(evt.target.result);

    if (!vrp.vrp) {
      alert("Fichier invalide");
      return false;
    }

    timer = displayTimer();

    $('#send-files').attr('disabled', true);
    $('#optim-infos').html('<span id="optim-status">' + i18n.optimizeLoading + '</span> <span id="avancement"></span> - <span id="timer"></span>');

    $.ajax({
      type: "POST",
      url: "/0.1/vrp/submit.json?api_key=" + getParams()['api_key'],
      data: JSON.stringify(vrp),
      success: function (result) {

        $('#optim-infos').append(' <input id="optim-job-uid" type="hidden" value="' + result.job.id + '"></input><button id="optim-kill">' + i18n.killOptim + '</button>');
        $('#optim-kill').click(function (e) {
          $.ajax({
            type: 'delete',
            url: '/0.1/vrp/jobs/' + $('#optim-job-uid').val() + '.json?api_key=' + getParams()["api_key"]
          }).done(function (result) {
            clearInterval(timer);
            jobsManager.stopJobChecking();
            $('#optim-infos').html('');
            displaySolution(lastSolution, { initForm: true });
          }).fail(function (jqXHR, textStatus) {
            alert(textStatus);
          });
          e.preventDefault();
          return false;
        });

        var lastSolution = null;
        var delay = 60000;
        jobsManager.checkJobStatus({
          job: result.job,
          format: '.json',
          interval: delay
        }, function (err, job) {
          if (err) {
            initForm();
            alert("An error occured");
            return;
          }
          // vrp returning csv, not json
          if (typeof job === 'string') {
            return displaySolution(job, {initForm: true});
          }

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
              $('#display-solution').click(function (e) {
                displaySolution(lastSolution);
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
            displaySolution(job.solutions[0], {initForm: true});
          }
          else if (job.job.status == 'failed' || job.job.status == 'killed') {
            if (debug) console.log('Job failed/killed: ' + JSON.stringify(job));
            alert(i18n.failureCallOptim(job.job.avancement));
            initForm();
          }
        });
      },
      error: function () {
        alert("An error occured");
        initForm();
      },
      dataType: 'json',
      contentType: "application/json"
    })
  };

  reader.readAsText(file);
  return false;
});

var displaySolution = function (solution, options) {
  if (typeof solution === 'string') {
    $('#infos').append(' - <a href="data:text/csv,' + encodeURIComponent(solution) + '">' + i18n.downloadCSV + '</a>');
    $('#result').html(solution);
  } else if (typeof solution !== 'string') {
    $('#infos').html('iterations: ' + solution.iterations + ' cost: <b>' + Math.round(solution.cost) + '</b> (time: ' + (solution.total_time && solution.total_time.toHHMMSS()) + ' distance: ' + Math.round(solution.total_distance / 1000) + ')');
    $('#infos').append(' - <a download="optimized.json" href="data:text/json;charset=utf-8,' + encodeURIComponent(JSON.stringify(solution)) + '">' + i18n.downloadJSON + '</a>');
    $('#result').html(JSON.stringify(solution, null, 4));
  }

  if (options && options.initForm)
    initForm();
};

var initForm = function() {
  jobsManager.stopJobChecking();
  clearInterval(timer);
  $('#send-files').attr('disabled', false);
  $('#optim-infos').html('');
};
