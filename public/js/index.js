
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
    alert(i18next.t('alert_need_file'));
    return false;
  }

  var reader = new FileReader();
  reader.onload = function (evt) {
    var vrp;
    try {
      vrp = JSON.parse(evt.target.result);
    } catch(e) {
      alert(i18next.t('invalid_json') + e);
      return false;
    }

    if (!vrp.vrp) {
      alert(i18next.t('invalid_file'));
      return false;
    }

    $('#send-files').attr('disabled', true);
    $('#optim-infos').html('<span id="optim-status">' + i18next.t('optimize_loading') + '</span> <span id="avancement"></span> - <span id="timer"></span>');

    jobsManager.submit({
      data: JSON.stringify(vrp),
      dataType: 'json',
      contentType: "application/json",
    }).done(function (submittedJob) {
      timer = displayTimer();
      $('#optim-infos').append(' <input id="optim-job-uid" type="hidden" value="' + submittedJob.job.id + '"></input><button id="optim-kill">' + i18next.t('kill_optim') + '</button>');
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
          alert(i18next.t('error'));
          return;
        }
        // vrp returning csv, not json
        if (typeof job === 'string') {
          return displaySolution(submittedJob.job.id, job, { initForm: true });
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
          alert(i18next.t('failure_call_optim', { error: job.job.avancement}));
          initForm();
        }
      });
    }).fail(function (xhr, status) {
      if (xhr.readyState !== 0 && xhr.status !== 0) {
        response = xhr.responseJSON
        alert(response['message'] || i18next.t('error'));
      }
      initForm();
    });
  };

  reader.readAsText(file);
  return false;
});
