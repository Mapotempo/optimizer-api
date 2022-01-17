'use-strict';

var timer = null;

$(document).ready(function() {

  jobsManager.ajaxGetJobs(true);

  $('#post-form').submit(function(e) {
    e.preventDefault();

    var filesConfigs = $('#json-config')[0].files;

    if (filesConfigs.length === 1) {
      $('#send-csvs').attr('disabled', true);

      var problem_data = new FormData(this);

      jobsManager.submit({
        contentType: false,
        cache: false,
        processData: false,
        data: problem_data
      }).done(function (response) {
        var job = response.job;
        $('#optim-infos').html('<span id="optim-status">' + i18next.t('optimize_loading') + '</span> <span id="avancement"></span> - <span id="timer"></span>');
        timer = displayTimer();
        if (job !== null) {
          jobsManager.checkJobStatus({
            job: job,
            interval: 5000
          }, function (err, job, xhr) {
            if (err) {
              $('#optim-infos').html(i18next.t('failure_call_optim', { error: err }));
              if (debug) console.log(err.status);
              return;
            }
            if (xhr.status == 200 && job.job && job.job.status == 'completed') {
              $('#optim-infos').html(i18next.t('optimize_finished'));
              displaySolution(job.job.id, job.solutions[0], { downloadButton: true });
              clearInterval(timer);
            } else if (xhr.status == 500) {
              initForm();
              $('#optim-infos').html(i18next.t('optimize_finished_error'));
              clearInterval(timer);
              if (debug) console.log(job);
            }
          })
        }
      }).fail(function (error) {
        initForm();
        $('#optim-infos').html(i18next.t('failure_call_optim', { error: error.responseJSON.message }));
        clearInterval(timer);
        if (debug) console.log(error.responseText);
      });

    } else {
      $('#optim-infos').html(i18next.t('invalid_config'));
    }
  });
});
