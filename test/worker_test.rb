require File.dirname(__FILE__) + '/test_helper'

context "Resque::Worker" do
  setup do
    Resque.redis.flush_all

    @worker = Resque::Worker.new(:jobs)
    Resque.enqueue(:jobs, SomeJob, 20, '/tmp')
  end

  test "can fail jobs" do
    Resque.enqueue(:jobs, BadJob)
    @worker.work(0)
    assert_equal 1, Resque::Job.failed_size
  end

  test "can peek at failed jobs" do
    10.times { Resque.enqueue(:jobs, BadJob) }
    @worker.work(0)
    assert_equal 10, Resque::Job.failed_size

    assert_equal 10, Resque::Job.failed(0, 20).size
  end

  test "catches exceptional jobs" do
    Resque.enqueue(:jobs, BadJob)
    Resque.enqueue(:jobs, BadJob)
    @worker.process
    @worker.process
    @worker.process
    assert_equal 2, Resque::Job.failed_size
  end

  test "can work on multiple queues" do
    Resque.enqueue(:high, GoodJob)
    Resque.enqueue(:critical, GoodJob)

    worker = Resque::Worker.new(:critical, :high)

    worker.process
    assert_equal 1, Resque.size(:high)
    assert_equal 0, Resque.size(:critical)

    worker.process
    assert_equal 0, Resque.size(:high)
  end

  test "has a unique id" do
    assert_equal "#{`hostname`.chomp}:#{$$}:jobs", @worker.to_s
  end

  test "complains if no queues are given" do
    assert_raise Resque::Worker::NoQueueError do
      Resque::Worker.new
    end
  end

  test "inserts itself into the 'workers' list on startup" do
    @worker.work(0) do
      assert_equal @worker, Resque.workers[0]
    end
  end

  test "removes itself from the 'workers' list on shutdown" do
    @worker.work(0) do
      assert_equal @worker, Resque.workers[0]
    end

    assert_equal [], Resque.workers
  end

  test "records what it is working on" do
    @worker.work(0) do
      task = @worker.job
      assert_equal({"args"=>[20, "/tmp"], "class"=>"SomeJob"}, task['payload'])
      assert task['run_at']
      assert_equal 'jobs', task['queue']
    end
  end

  test "clears its status when not working on anything" do
    @worker.work(0)
    assert_equal Hash.new, @worker.job
  end

  test "knows when it is working" do
    @worker.work(0) do
      assert @worker.working?
    end
  end

  test "knows when it is idle" do
    @worker.work(0)
    assert @worker.idle?
  end

  test "knows who is working" do
    @worker.work(0) do
      assert_equal [@worker.to_s], Resque.working
    end
  end

  test "keeps track of how many jobs it has processed" do
    Resque.enqueue(:jobs, BadJob)
    Resque.enqueue(:jobs, BadJob)

    3.times do
      job = @worker.reserve
      @worker.process job
    end
    assert_equal 3, @worker.processed
  end

  test "keeps track of how many failures it has seen" do
    Resque.enqueue(:jobs, BadJob)
    Resque.enqueue(:jobs, BadJob)

    3.times do
      job = @worker.reserve
      @worker.process job
    end
    assert_equal 2, @worker.failed
  end

  test "stats are erased when the worker goes away" do
    @worker.work(0)
    assert_equal 0, @worker.processed
    assert_equal 0, @worker.failed
  end

  test "knows when it started" do
    time = Time.now
    @worker.work(0) do
      assert_equal time.to_s, @worker.started.to_s
    end
  end

  test "knows whether it exists or not" do
    @worker.work(0) do
      assert Resque::Worker.exists?(@worker)
      assert !Resque::Worker.exists?('blah-blah')
    end
  end

  test "sets $0 while working" do
    @worker.work(0) do
      assert_equal "resque: Processing jobs since #{Time.now.to_i}", $0
    end
  end

  test "can be found" do
    @worker.work(0) do
      found = Resque::Worker.find(@worker.to_s)
      assert_equal @worker.to_s, found.to_s
      assert found.working?
      assert_equal @worker.job, found.job
    end
  end

  test "doesn't find fakes" do
    @worker.work(0) do
      found = Resque::Worker.find('blah-blah')
      assert_equal nil, found
    end
  end

  test "cleans up dead worker info on start (crash recovery)" do
    # first we fake out two dead workers
    workerA = Resque::Worker.new(:jobs)
    workerA.instance_variable_set(:@to_s, "#{`hostname`.chomp}:1:jobs")
    workerA.register_worker

    workerB = Resque::Worker.new(:high, :low)
    workerB.instance_variable_set(:@to_s, "#{`hostname`.chomp}:2:high,low")
    workerB.register_worker

    assert_equal 2, Resque.workers.size

    # then we prune them
    @worker.work(0) do
      assert_equal 1, Resque.workers.size
    end
  end
end
