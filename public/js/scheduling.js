'use-strict';

var timer = null;

$(document).ready(function() {

  $('#send-csvs').append(i18n.form['send-csvs']);
  $('#status-label').append(i18n.form['status-label']);
  $('#csv-points-label').append(i18n.form['csv-points-label']);
  $('#csv-units-label').append(i18n.form['csv-units-label']);
  $('#csv-capacities-label').append(i18n.form['csv-capacities-label']);
  $('#csv-quantities-label').append(i18n.form['csv-quantities-label']);
  $('#csv-timewindows-label').append(i18n.form['csv-timewindows-label']);
  $('#csv-services-label').append(i18n.form['csv-services-label']);
  $('#csv-shipments-label').append(i18n.form['csv-shipments-label']);
  $('#csv-vehicles-label').append(i18n.form['csv-vehicles-label']);
  $('#json-config-label').append(i18n.form['json-config-label']);

  $('#optim-infos').html(i18n.waitingSubmit);

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
        $('#optim-infos').html('<span id="optim-status">' + i18n.optimizeLoading + '</span> <span id="avancement"></span> - <span id="timer"></span>');
        timer = displayTimer();
        if (job !== null) {
          jobsManager.checkJobStatus({
            job: job,
            interval: 5000
          }, function (err, job, xhr) {
            if (err) {
              $('#optim-infos').html(i18n.failureCallOptim(err));
              if (debug) console.log(err.status);
              return;
            }
            if (xhr.status == 200 && job.job && job.job.status == 'completed') {
              $('#optim-infos').html(i18n.optimizeFinished);
              displaySolution(job.job.id, job.solutions[0], { downloadButton: true });
              clearInterval(timer);
            } else if (xhr.status == 500) {
              initForm();
              $('#optim-infos').html(i18n.optimizeFinishedError);
              clearInterval(timer);
              if (debug) console.log(job);
            }
          })
        }
      }).fail(function (error) {
        initForm();
        $('#optim-infos').html(i18n.failureCallOptim('Vérification des fichiers requise - ' + error.responseJSON.message ));
        clearInterval(timer);
        if (debug) console.log(error.responseText);
      });

    } else {
      $('#optim-infos').html(i18n.form.invalidConfig);
    }
  });
});
