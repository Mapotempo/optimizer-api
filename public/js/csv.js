'use-strict';


$(document).ready(function() {

  $('#send-csvs').append(i18n.form['send-csvs']);
  $('#status-label').append(i18n.form['status-label']);
  $('#csv-points-label').append(i18n.form['csv-points-label']);
  $('#csv-timewindows-label').append(i18n.form['csv-timewindows-label']);
  $('#csv-services-label').append(i18n.form['csv-services-label']);
  $('#csv-vehicles-label').append(i18n.form['csv-vehicles-label']);
  $('#json-config-label').append(i18n.form['json-config-label']);

  $('#infos').html(i18n.waitingSubmit);

  $('#post-form').submit(function(e) {
    e.preventDefault();

    var filesConfigs = $('#json-config')[0].files;

    if (filesConfigs.length === 1) {
      $('#send-csvs').attr('disabled', true);

      var problem_data = new FormData( this );

      $.ajax({
        url: '/0.1/vrp/submit.json?api_key=' + getParams()["api_key"],
        type: 'POST',
        contentType: false,
        cache: false,
        processData: false,
        data: problem_data
      })
      .done(function(response) {
        var jobId = response.job.id;
        if (jobId != null)
          watchJobUpdate(jobId);

      })
      .fail(function(error) {
        $('#infos').html(i18n.failureCallOptim('Vérification des fichiers requise'));
        console.log(error.responseText);
      });

    } else {
      $('#infos').html(i18n.form.invalidConfig);
    }
  });

  watchJobUpdate = function(jobId) {
    var check_job = function() {

      $('#infos').html(i18n.optimizeLoading);
      $.ajax({
        url: '/0.1/vrp/jobs/' + jobId + '.csv?api_key=' + getParams()["api_key"],
        type: 'GET',
      })
      .done(function(response, responseText, XHR) {

        if (XHR.status == 200) {
          $('#infos').html(i18n.optimizeFinished);
          if (response instanceof Object && 'solutions' in response) {
            self.solutionJSON = (response.solutions);
          } else {
            var a         = document.createElement('a');
            a.href        = 'data:attachment/csv,' +  encodeURIComponent(response);
            a.target      = '_blank';
            a.download    = 'result.csv';
            document.body.appendChild(a);
            a.click();
          }

          clearInterval(timeOut);
        } else if (XHR.status == 202) {
          $('#infos').html(i18n.optimizeFinishedError);
          console.log(response);
          clearInterval(timeOut);
        }
      })
      .fail(function(err) {
        $('#infos').html(i18n.failureCallOptim(err));
        console.log(err.status);
      })
    }

    var timeOut = setInterval(check_job, 3000);
  }
});
