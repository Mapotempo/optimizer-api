# Copyright © Mapotempo, 2019
#
# This file is part of Mapotempo.
#
# Mapotempo is free software. You can redistribute it and/or
# modify since you respect the terms of the GNU Affero General
# Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Mapotempo is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Mapotempo. If not, see:
# <http://www.gnu.org/licenses/agpl.html>
#
require './test/test_helper'

module TestHelper
  include Rack::Test::Methods
  def wait_avancement_match(job_id, avancement_regexp, options)
    puts "#{job_id} #{Time.now} waiting avancement to match '#{avancement_regexp}'"
    last_response_body = nil
    loop do
      get "0.1/vrp/jobs/#{job_id}.json", options

      assert_equal 200, last_response.status, 'Response status code should be 200'
      last_response_body = JSON.parse(last_response.body)
      assert_includes ['queued', 'working', 'completed'], last_response_body['job']['status']

      puts "Empty response body: #{last_response_body}" if last_response_body.nil? || last_response_body['job'].nil?

      break if avancement_regexp.match?(last_response_body['job']['avancement'])

      sleep 0.1
    end
    puts "#{job_id} #{Time.now} got avancement '#{last_response_body['job']['avancement']}' to match #{avancement_regexp}"
    last_response_body
  end

  def wait_status(job_id, status, options)
    puts "#{job_id} #{Time.now} waiting #{status} status"
    loop do
      get "0.1/vrp/jobs/#{job_id}.json", options

      assert_equal 200, last_response.status, 'Response status code should be 200'
      assert_includes ['queued', 'working', 'completed'], JSON.parse(last_response.body)['job']['status']

      puts "Empty response body: #{JSON.parse(last_response.body)}" if JSON.parse(last_response.body).nil? || JSON.parse(last_response.body)['job'].nil?

      break if JSON.parse(last_response.body)['job']['status'] == status

      sleep 0.1
    end
    puts "#{job_id} #{Time.now} got #{status} status"
    JSON.parse(last_response.body)
  end

  def wait_status_csv(job_id, status, options)
    language = options[:http_accept_language] || :legacy
    options.delete(:http_accept_language)
    puts "#{job_id} #{Time.now} waiting #{status} status_csv"
    loop do
      get "0.1/vrp/jobs/#{job_id}", options, 'HTTP_ACCEPT_LANGUAGE' => language

      assert_equal 200, last_response.status, 'Response status code should be 200'

      break if last_response.content_type == 'text/csv;'

      assert_includes ['queued', 'working', 'completed'], JSON.parse(last_response.body)['job']['status']

      puts "Empty response body: #{JSON.parse(last_response.body)}" if JSON.parse(last_response.body).nil? || JSON.parse(last_response.body)['job'].nil?

      break if JSON.parse(last_response.body)['job']['status'] == status

      sleep 0.1
    end
    puts "#{job_id} #{Time.now} got #{status} status_csv"
    last_response.body
  end

  def submit_vrp(params)
    hex = Digest::MD5.hexdigest params.to_s
    puts "#{hex} #{Time.now} submiting #{hex}"
    post '/0.1/vrp/submit', params.to_json, 'CONTENT_TYPE' => 'application/json'
    assert_includes [200, 201], last_response.status
    assert last_response.body
    if last_response.status == 201
      job_id = JSON.parse(last_response.body)['job']['id']
      assert job_id
      puts "#{job_id} #{Time.now} submitted #{hex}"
      job_id
    else
      response = JSON.parse(last_response.body)
      puts "#{job_id} #{Time.now} submitted #{hex} but it returned a result"
      assert response['job']['status']['completed'] || response['job']['status']['queued']
    end
  end

  def submit_csv(params)
    language = params[:http_accept_language] || :legacy
    params.delete(:http_accept_language)
    hex = Digest::MD5.hexdigest params.to_s
    puts "#{hex} #{Time.now} submiting_csv #{hex}"
    post '/0.1/vrp/submit', params.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT_LANGUAGE' => language
    assert_includes [200, 201], last_response.status
    assert last_response.body
    if last_response.status == 201
      job_id = JSON.parse(last_response.body)['job']['id']
      assert job_id
      puts "#{job_id} #{Time.now} submitted_csv #{hex}"
      job_id
    else
      response = last_response.body.slice(1..-1).split('\n').map{ |line| line.split(',') }
      puts "#{job_id} #{Time.now} submitted_csv #{hex} but it returned a result"
      response
    end
  end

  def delete_job(job_id, params)
    puts "#{job_id} #{Time.now} sending delete"
    delete "0.1/vrp/jobs/#{job_id}.json", params
    assert_equal 202, last_response.status, last_response.body
    puts "#{job_id} #{Time.now} delete done"
    JSON.parse(last_response.body)
  end

  def delete_completed_job(job_id, params)
    puts "#{job_id} #{Time.now} sending delete_completed"
    delete "0.1/vrp/jobs/#{job_id}.json", params
    assert_equal 404, last_response.status, last_response.body
    puts "#{job_id} #{Time.now} delete_completed done"
    JSON.parse(last_response.body)
  end

  def asynchronously(options = {start_worker: false})
    old_config_solve_synchronously = OptimizerWrapper.config[:solve][:synchronously]
    OptimizerWrapper.config[:solve][:synchronously] = false
    old_resque_inline = Resque.inline
    Resque.inline = false
    if options[:start_worker]
      pid_worker = Process.spawn({ 'COUNT' => '1', 'QUEUE' => 'DEFAULT' }, 'bundle exec rake resque:workers --trace', pgroup: true) # don't create another shell
      pgid_worker = Process.getpgid(pid_worker)
      while `ps -o pgid | grep #{pgid_worker}`.split(/\n/).size < 2
        puts "#{Time.now} Waiting for the worker to launch"
        sleep 0.1
      end
      puts "#{Time.now} Worker is started"
      sleep 0.1
    end
    yield
  ensure
    Resque.inline = old_resque_inline
    OptimizerWrapper.config[:solve][:synchronously] = old_config_solve_synchronously
    if options[:start_worker] && pgid_worker
      # Kill all grandchildren
      worker_pids = `ps -o pgid,pid | grep #{pgid_worker}`.split(/\n/)
      worker_pids.collect!{ |i| i.split(' ')[-1].to_i }
      worker_pids.sort!
      worker_pids.reverse_each{ |pid|
        next if pid == pgid_worker

        Process.kill('SIGKILL', pid)
        Process.detach(pid)
      }
      Process.kill('SIGTERM', -pgid_worker) # Kill the process group (this doesn't kill grandchildren)
      Process.waitpid(-pgid_worker, 0)
      while `ps -o pgid,pid | grep "#{worker_pids.join('\|')}"`.split(/\n/).any?
        puts "#{Time.now} Waiting the worker process group #{pgid_worker} to die\n"
        sleep 0.1
      end
      puts "#{Time.now} Worker is killed"
    end
  end
end
