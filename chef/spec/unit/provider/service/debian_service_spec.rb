#
# Author:: AJ Christensen (<aj@hjksolutions.com>)
# Copyright:: Copyright (c) 2008 HJK Solutions, LLC
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "..", "spec_helper"))

describe Chef::Provider::Service::Debian, "load_current_resource" do
  before(:each) do
    @node = Chef::Node.new
    @node[:command] = {:ps => 'fuuuu'}
    @run_context = Chef::RunContext.new(@node, {})

    @new_resource = Chef::Resource::Service.new("chef")

    @current_resource = Chef::Resource::Service.new("chef")

    @provider = Chef::Provider::Service::Debian.new(@new_resource, @run_context)
    @provider.current_resource = @current_resource

    @pid, @stdin, @stdout, @stderr = nil, nil, nil, nil

  end

  it "ensures /usr/sbin/update-rc.d is available" do
    File.should_receive(:exists?).with("/usr/sbin/update-rc.d").and_return(false)
    lambda { @provider.assert_update_rcd_available }.should raise_error(Chef::Exceptions::Service)
  end


  {"Debian/Lenny and older" => {
      "linked" => {
        "stdout" => " Removing any system startup links for /etc/init.d/chef ...
   /etc/rc0.d/K20chef
   /etc/rc1.d/K20chef
   /etc/rc2.d/S20chef
   /etc/rc3.d/S20chef
   /etc/rc4.d/S20chef
   /etc/rc5.d/S20chef
   /etc/rc6.d/K20chef",
        "stderr" => ""
      },
      "not linked" => {
        "stdout" => " Removing any system startup links for /etc/init.d/chef ...",
        "stderr" => ""
      },
    },
    "Debian/Squeeze and earlier" => {
      "linked" => {
        "stdout" => "update-rc.d: using dependency based boot sequencing",
        "stderr" => "insserv: remove service /etc/init.d/../rc0.d/K20chef-client
insserv: remove service /etc/init.d/../rc1.d/K20chef-client
insserv: remove service /etc/init.d/../rc2.d/S20chef-client
insserv: remove service /etc/init.d/../rc3.d/S20chef-client
insserv: remove service /etc/init.d/../rc4.d/S20chef-client
insserv: remove service /etc/init.d/../rc5.d/S20chef-client
insserv: remove service /etc/init.d/../rc6.d/K20chef-client
insserv: dryrun, not creating .depend.boot, .depend.start, and .depend.stop"
      },
      "not linked" => {
        "stdout" => "update-rc.d: using dependency based boot sequencing",
        "stderr" => ""
      }
    }
  }.each do |model, streams|
    describe "when update-rc.d shows the init script linked to rc*.d/" do
      before do
        @provider.stub!(:run_command)
        @provider.stub!(:assert_update_rcd_available)
        @status = mock("Status", :exitstatus => 0)

        @stdout = StringIO.new(streams["linked"]["stdout"])
        @stderr = StringIO.new(streams["linked"]["stderr"])
        @provider.stub!(:popen4).and_yield(@pid, @stdin, @stdout, @stderr).and_return(@status)
      end

      it "says the service is enabled" do
        @provider.service_currently_enabled?.should be_true
      end

      it "stores the 'enabled' state" do
        Chef::Resource::Service.stub!(:new).and_return(@current_resource)
        @provider.load_current_resource.should equal(@current_resource)
        @current_resource.enabled.should be_true
      end

      it "stores the start/stop priorities of the service" do
        @provider.load_current_resource
        expected_priorities = {"6"=>[:stop, "20"],
          "0"=>[:stop, "20"],
          "1"=>[:stop, "20"],
          "2"=>[:start, "20"],
          "3"=>[:start, "20"],
          "4"=>[:start, "20"],
          "5"=>[:start, "20"]}
        @provider.current_resource.priority.should == expected_priorities
      end
    end

    describe "when using squeeze/earlier and update-rc.d shows the init script isn't linked to rc*.d" do
      before do
        @provider.stub!(:run_command)
        @provider.stub!(:assert_update_rcd_available)
        @status = mock("Status", :exitstatus => 0)
        @stdout = StringIO.new(streams["not linked"]["stdout"])
        @stderr = StringIO.new(streams["not linked"]["stderr"])
        @provider.stub!(:popen4).and_yield(@pid, @stdin, @stdout, @stderr).and_return(@status)
      end

      it "says the service is disabled" do
        @provider.service_currently_enabled?.should be_false
      end

      it "stores the 'disabled' state" do
        Chef::Resource::Service.stub!(:new).and_return(@current_resource)
        @provider.load_current_resource.should equal(@current_resource)
        @current_resource.enabled.should be_false
      end
    end
  end

  describe "when update-rc.d fails" do
    before do
      @status = mock("Status", :exitstatus => -1)
      @provider.stub!(:popen4).and_return(@status)
    end

    it "raises an error" do
      lambda { @provider.service_currently_enabled? }.should raise_error(Chef::Exceptions::Service)
    end
  end

  describe "when enabling a service without priority" do
    it "should call update-rc.d 'service_name' defaults" do
      @provider.should_receive(:run_command).with({:command => "/usr/sbin/update-rc.d #{@new_resource.service_name} defaults"})
      @provider.enable_service()
    end
  end

  describe "when enabling a service with simple priority" do
    before do
      @new_resource.priority(75)
    end

    it "should call update-rc.d 'service_name' defaults" do
      @provider.should_receive(:run_command).with({:command => "/usr/sbin/update-rc.d #{@new_resource.service_name} defaults 75 25"})
      @provider.enable_service()
    end
  end

  describe "when enabling a service with complex priorities" do
    before do
      @new_resource.priority(2 => [:start, 20], 3 => [:stop, 55])
    end

    it "should call update-rc.d 'service_name' defaults" do
      @provider.should_receive(:run_command).with({:command => "/usr/sbin/update-rc.d #{@new_resource.service_name} start 20 2 . stop 55 3 . "})
      @provider.enable_service()
    end
  end

  describe "when disabling a service" do
    it "should call update-rc.d 'service_name' disable" do
      @provider.should_receive(:run_command).with({:command => "/usr/sbin/update-rc.d #{@new_resource.service_name} disable"})
      @provider.disable_service()
    end
  end
end
