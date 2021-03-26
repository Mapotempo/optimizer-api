
var jobStatusTimeout = null;
var requestPendingAllJobs = false;

function buildDownloadLink(jobId, state) {
  var extension = state === 'failed' ? '.json' : '';
  var msg = state === 'failed'
          ? 'Télécharger le rapport d\'erreur de l\'optimisation'
          : 'Télécharger le résultat de l\'optimisation';

  var url = "/0.1/vrp/jobs/" + jobId + extension + '?api_key=' + getParams()['api_key'];

  return ' <a download="result_' + jobId + ((extension !== '.json' ? '.csv' : extension))
    + '" href="' + url + '">' + msg + '</a>';
}

function buildResultLink(jobId) {
  return '<a href="/result.html?api_key=' + getParams()['api_key'] + '&job_id=' + jobId + '" target="_blank">Visualiser les résultats</a>'
}

var jobsManager = {
  jobs: [],
  htmlElements: {
    builder: function (jobs) {
      $(jobs).each(function () {

        currentJob = this;
        var donwloadBtn = currentJob.status === 'completed' || currentJob.status === 'failed';
        var startTime = (new Date(currentJob.time)).toLocaleString('fr-FR');
        var completedDate = ''

        if (currentJob.status === 'completed') {
          var splitedDate = currentJob.avancement
            .replace("Completed at ", '')
            .split(' ');

          completedDate = ' ' + (new Date(`${splitedDate[0]}T${splitedDate[1]}${splitedDate[2]}`)).toLocaleString('fr-FR');
        }


        var jobDOM =
          '<div class="job">'
          + '<span class="optim-start">' + startTime + ' : </span>'
          + '<span class="job_title">' + 'Job N° <b>' + currentJob.uuid + '</b></span> '
          + '<button value=' + currentJob.uuid + ' data-role="delete">'
          + ((currentJob.status === 'queued' || currentJob.status === 'working') ? i18n.killOptim : i18n.deleteOptim)
          + '</button>'
          + ' (Status: ' + currentJob.status + completedDate + ')'
          + (donwloadBtn ? buildDownloadLink(currentJob.uuid, currentJob.status) : '')
          + (currentJob.status === 'completed' ? ' - ' + buildResultLink(currentJob.uuid) : '')
          + '</div>';

        $('#jobs-list').append(jobDOM);

      });
      $('#jobs-list button').on('click', function () {
        jobsManager.roleDispatcher(this);
      });
    }
  },
  roleDispatcher: function (object) {
    switch ($(object).data('role')) {
      case 'focus':
        //actually in building, create to apply different behavior to the button object restartJob, actually not set. #TODO
        break;
      case 'delete':
        this.ajaxDeleteJob($(object).val());
        break;
    }
  },
  ajaxGetJobs: function (timeinterval) {
    var ajaxload = function () {
      if (!requestPendingAllJobs) {
        requestPendingAllJobs = true;
        $.ajax({
          url: '/0.1/vrp/jobs',
          type: 'get',
          dataType: 'json',
          data: { api_key: getParams()['api_key'] },
          complete: function () { requestPendingAllJobs = false; }
        }).done(function (data) {
          jobsManager.shouldUpdate(data);
        }).fail(function (jqXHR, textStatus, errorThrown) {
          if (jqXHR.status !== 500) {
            clearInterval(window.AjaxGetRequestInterval);
          }
          if (jqXHR.status == 401) {
            $('#optim-list-status').prepend('<div class="error">' + i18n.unauthorizedError + '</div>');
            $('form input, form button').prop('disabled', true);
          }
        });
      }
    };
    if (timeinterval) {
      ajaxload();
      window.AjaxGetRequestInterval = setInterval(ajaxload, 5000);
    } else {
      ajaxload();
    }
  },
  ajaxDeleteJob: function (uuid) {
    $.ajax({
      url: '/0.1/vrp/jobs/' + uuid,
      type: 'delete',
      dataType: 'json',
      data: {
        api_key: getParams()['api_key']
      },
    }).done(function (data) {
      if (debug) { console.log("the uuid has been deleted from the jobs queue & the DB"); }
      $('button[data-role="delete"][value="' + uuid + '"]').fadeOut(500, function () { $(this).closest('.job').remove(); });
    });
  },
  shouldUpdate: function (data) {
    // erase list if no job running
    if (data.length === 0 && jobsManager.jobs.length !== 0) {
      $('#jobs-list').empty();
    }
    //check if chagements occurs in the data api. #TODO, update if more params are needed.
    $(data).each(function (index, object) {
      if (jobsManager.jobs.length > 0) {
        if (object.status != jobsManager.jobs[index].status || jobsManager.jobs.length != data.length) {
          jobsManager.jobs = data;
          $('#jobs-list').empty();
          jobsManager.htmlElements.builder(jobsManager.jobs);
        }
      }
      else {
        jobsManager.jobs = data;
        $('#jobs-list').empty();
        jobsManager.htmlElements.builder(jobsManager.jobs);
      }
    });
  },
  checkJobStatus: function (options, cb) {
    var nbError = 0;
    var requestPendingJobTimeout = false;

    if (options.interval) {
      jobStatusTimeout = setTimeout(requestPendingJob, options.interval);
      return;
    }

    requestPendingJob();

    function requestPendingJob() {
      $.ajax({
        type: 'GET',
        contentType: 'application/json',
        url: '/0.1/vrp/jobs/'
          + (options.job.id || options.job.uuid)
          // + (options.format ? options.format : '')
          + '.json?api_key=' + getParams()["api_key"],
        success: function (job, _, xhr) {
          if (options.interval && checkJSONJob(job)) {
            if (debug) console.log("REQUEST PENDING JOB", checkJSONJob(job));
            requestPendingJobTimeout = true;
          }

          nbError = 0;
          cb(null, job, xhr);
        },
        error: function (xhr, status) {
          ++nbError
          if (nbError > 2) {
            cb({ xhr, status });
            return alert(i18n.failureOptim(nbError, status));
          }
          requestPendingJobTimeout = true;
        },
        complete: function () {
          if (requestPendingJobTimeout) {
            requestPendingJobTimeout = false;

            // interval max: 1mins
            options.interval *= 2;
            if (options.interval > 60000) {
              options.interval = 60000
            }

            jobStatusTimeout = setTimeout(requestPendingJob, options.interval);
          }
        }
      });
    }
  },
  stopJobChecking: function () {
    requestPendingJobTimeout = false;
    clearTimeout(jobStatusTimeout);
  },
  submit: function (options) {
    const params = buildParams({
      type: "POST",
      url: "/0.1/vrp/submit.json?api_key=" + getParams()['api_key']
    }, options);
    return $.ajax(params);
  },
  delete: function (jobId) {
    return $.ajax({
      type: 'delete',
      url: '/0.1/vrp/jobs/' + jobId + '.json?api_key=' + getParams()["api_key"]
    }).done(function () { jobsManager.stopJobChecking(); })
      .fail(function (jqXHR, textStatus) { alert(textStatus); });
  },
  getCSV: function (jobId, cb) {
    return $.ajax({
      type: 'get',
      url: '/0.1/vrp/jobs/' + jobId + '.csv?api_key=' + getParams()["api_key"],
      success: function (content) {
        cb(content);
      }
    }).done(function () { jobsManager.stopJobChecking(); })
      .fail(function (jqXHR, textStatus) { alert(textStatus); });
  }
};

function checkJSONJob(job) {
  if (debug) console.log("JOB: ", job, (job.job && job.job.status !== 'completed'));
  return ((job.job && job.job.status !== 'completed'))
}

function buildParams(base, params) {
  return Object
    .keys(params)
    .reduce(function (acc, key) {
      acc[key] = params[key]
      return acc
    }, base);
}

function downloadButton(jobId, content) {
  var a = document.createElement('a');
  a.href = content;
  a.target = '_blank';
  a.download = 'result_' + jobId + '.csv';
  document.body.appendChild(a);
  a.click();
}
