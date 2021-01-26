
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
    var vrp;
    try {
      vrp = JSON.parse(evt.target.result);
    } catch(e) {
      alert("Le fichier fourni n'est pas dans un format JSON valide :\n" + e);
      return false;
    }

    if (!vrp.vrp) {
      alert("Fichier invalide");
      return false;
    }

    $('#send-files').attr('disabled', true);
    $('#optim-infos').html('<span id="optim-status">' + i18n.optimizeLoading + '</span> <span id="avancement"></span> - <span id="timer"></span>');

    jobsManager.submit({
      data: JSON.stringify(vrp),
      dataType: 'json',
      contentType: "application/json",
    }).done(function (submittedJob) {
      timer = displayTimer();
      $('#optim-infos').append(' <input id="optim-job-uid" type="hidden" value="' + submittedJob.job.id + '"></input><button id="optim-kill">' + i18n.killOptim + '</button>');
      $('#optim-kill').click(function (e) {
        jobsManager.delete($('#optim-job-uid').val())
          .done(function () {
            $('#optim-infos').html('');
            displaySolution(submittedJob, lastSolution, { initForm: true });
          });
        e.preventDefault();
        return false;
      });

      var lastSolution = null;
      var delay = 5000;
      jobsManager.checkJobStatus({
        job: submittedJob.job,
        interval: delay
      }, function (err, job) {
        if (err) {
          initForm();
          clearInterval(timer);
          alert("An error occured");
          return;
        }
        // vrp returning csv, not json
        if (typeof job === 'string') {
          return displaySolution(submittedJob.job.id, job, { initForm: true });
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
              displaySolution(submittedJob.job.id, lastSolution);
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
          displaySolution(submittedJob.job.id, job.solutions[0], { downloadButton: true });
        }
        else if (job.job.status == 'failed' || job.job.status == 'killed') {
          if (debug) console.log('Job failed/killed: ' + JSON.stringify(job));
          alert(i18n.failureCallOptim(job.job.avancement));
          initForm();
        }
      });
    }).fail(function (xhr, status) {
      if (xhr.readyState !== 0 && xhr.status !== 0) {
        response = xhr.responseJSON
        alert(response['message'] || "An error occured");
      }
      initForm();
    });
  };

  reader.readAsText(file);
  return false;
});
