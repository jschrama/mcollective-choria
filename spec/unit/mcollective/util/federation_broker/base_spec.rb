require "spec_helper"
require "mcollective/util/federation_broker"

module MCollective
  module Util
    class FederationBroker
      describe Base do
        let(:fb) { stub(:cluster_name => "rspec", :instance_name => "a") }
        let(:inbox) { stub }
        let(:outbox) { stub }
        let(:nats) { stub(:connected_server => "rspec.local") }
        let(:base) { Base.new(fb, inbox, outbox) }

        before(:each) do
          NatsWrapper.expects(:new).returns(nats)
          base.stubs(:processor_type).returns("rspec_processor")
          base.stubs(:queue).returns(
            :name => "rspec.target",
            :queue => "rspec"
          )
        end

        describe "#consume" do
          it "should consume from the queue and process messages" do
            base.expects(:consume_from).with(base.queue).yields(JSON.dump("x" => "y"))
            base.expects(:should_process?).with("x" => "y").returns(true)
            base.expects(:process).with("x" => "y")
            base.consume
          end

          it "should not process message that do not validate" do
            base.expects(:consume_from).with(base.queue).yields(JSON.dump("x" => "y"))
            base.expects(:should_process?).with("x" => "y").returns(false)
            base.expects(:process).never
            base.consume
          end
        end

        describe "#start_connection_and_handlers" do
          it "should start the connection, handler and consumer" do
            base.stubs(:servers).returns(["nats://1.example"])
            base.choria.stubs(:ssl_context).returns(:ssl => :context)
            base.connection.expects(:start).with(
              :max_reconnect_attempts => -1,
              :reconnect_time_wait => 1,
              :name => "fedbroker_rspec_a",
              :servers => ["nats://1.example"],
              :tls => {
                :context => {:ssl => :context}
              }
            )
            base.expects(:inbox_handler)
            base.expects(:consume)
            base.start_connection_and_handlers
          end
        end

        describe "#handle_inbox_item" do
          it "should publish all targets" do
            base.connection.expects(:publish).with("target.1", "x")
            base.connection.expects(:publish).with("target.2", "x")
            base.handle_inbox_item(:targets => ["target.1", "target.2"], :data => "x")
          end
        end

        describe "#record_seen" do
          it "should support recording the route" do
            fb.stubs(:connections).returns(
              "federation" => stub(:connected_server => "fed_nats1"),
              "collective" => stub(:connected_server => "c_nats1")
            )

            base.expects(:processor_type).returns("collective").twice
            base.record_seen(headers = {"seen-by" => [["x", "y"]]})
            expect(headers["seen-by"]).to eq([["x", "y"], ["c_nats1", "rspec:a", "fed_nats1"]])

            base.expects(:processor_type).returns("federation").twice
            base.record_seen(headers = {"seen-by" => [["x", "y"]]})
            expect(headers["seen-by"]).to eq([["x", "y"], ["fed_nats1", "rspec:a", "c_nats1"]])
          end
        end

        describe "#stats" do
          it "should report the right stats" do
            base.stubs(:queue).returns(
              :name => "rspec.target",
              :queue => "rspec"
            )

            inbox.expects(:size).returns(10)
            expect(base.stats).to eq(
              "connected_server" => "rspec.local",
              "last_message" => 0,
              "work_queue" => 10,
              "sent" => 0,
              "received" => 0,
              "source" => "rspec.target"
            )
          end
        end

        describe "#federation_source_name" do
          it "should create the right data" do
            expect(base.federation_source_name).to eq("choria.federation.rspec.federation")
          end
        end

        describe "#collective_source_name" do
          it "should create the right data" do
            expect(base.collective_source_name).to eq("choria.federation.rspec.collective")
          end
        end
      end
    end
  end
end
