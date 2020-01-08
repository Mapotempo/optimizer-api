'use-strict';


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

  $('#infos').html(i18n.waitingSubmit);

  jobsManager.ajaxGetJobs(true);

  $('#post-form').submit(function(e) {
    e.preventDefault();

    var filesConfigs = $('#json-config')[0].files;

    if (filesConfigs.length === 1) {
      $('#send-csvs').attr('disabled', true);

      var problem_data = new FormData(this);

      $.ajax({
        url: '/0.1/vrp/submit.json?api_key=' + getParams()["api_key"],
        type: 'POST',
        contentType: false,
        cache: false,
        processData: false,
        data: problem_data
      }).done(function (response) {
        var job = response.job;
        $('#infos').html(i18n.optimizeLoading);
        if (job !== null) {
          jobsManager.checkJobStatus({
            job: job,
            interval: 5000
          }, function (err, job, xhr) {
            if (err) {
              $('#infos').html(i18n.failureCallOptim(err));
              console.log(err.status);
              return;
            }

            if (xhr.status == 200) {
              $('#infos').html(i18n.optimizeFinished);
              if (job instanceof Object && 'solutions' in response) {
                self.solutionJSON = (job.solutions);
              } else {
                var a = document.createElement('a');
                a.href = 'data:attachment/csv,' + encodeURIComponent(job);
                a.target = '_blank';
                a.download = 'result.csv';
                document.body.appendChild(a);
                a.click();
              }
            } else if (xhr.status == 202) {
              $('#infos').html(i18n.optimizeFinishedError);
              if (debug) console.log(job)
            }

          })
        }
      }).fail(function (error) {
        $('#infos').html(i18n.failureCallOptim('Vérification des fichiers requise'));
        console.log(error.responseText);
      });

    } else {
      $('#infos').html(i18n.form.invalidConfig);
    }
  });
});
