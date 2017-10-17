'use-strict';


$(document).ready(function() {

    $('#send-csvs').append(i18n.form['send-csvs']);
    $('#csv-points-label').append(i18n.form['csv-points-label']);
    $('#csv-services-label').append(i18n.form['csv-services-label']);
    $('#csv-vehicles-label').append(i18n.form['csv-vehicles-label']);
    $('#json-config-label').append(i18n.form['json-config-label']);

   $('#lalala').submit(function(e) {
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
          watchJobStateFor(jobId);

      })
      .fail(function(error) {
        console.log(error.responseText);
      });

    }
  });

   watchJobStateFor = function(jobId) {
    var lala = function() {
      $.ajax({
        url: '/0.1/vrp/jobs/' + jobId + '.csv?api_key=' + getParams()["api_key"],
        type: 'GET',
      })
      .done(function(response, responseText, XHR) {

        if (XHR.status == 200) {
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
          console.log(response);
          clearInterval(timeOut);
        }
      })
      .fail(function(err) {
        console.log(err.status);
      })
    }

    var timeOut = setInterval(lala, 3000);
  }

  function IsJsonString(str) {
    try {
      JSON.parse(str);
    } catch (e) {
      console.log("err:; " , e);
      return false;
    }
    return true;
  }

});

