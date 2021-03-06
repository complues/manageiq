require "spec_helper"

describe ManageIQ::Providers::Openstack::InfraManager do
  it ".ems_type" do
    described_class.ems_type.should == 'openstack_infra'
  end

  it ".description" do
    described_class.description.should == 'OpenStack Platform Director'
  end

  describe ".metrics_collector_queue_name" do
    it "returns the correct queue name" do
      worker_queue = ManageIQ::Providers::Openstack::InfraManager::MetricsCollectorWorker.default_queue_name
      expect(described_class.metrics_collector_queue_name).to eq(worker_queue)
    end
  end

  context "validation" do
    before :each do
      @ems = FactoryGirl.create(:ems_openstack_infra_with_authentication)
      require 'openstack/openstack_event_monitor'
    end

    it "verifies AMQP credentials" do
      EvmSpecHelper.stub_amqp_support

      creds = {}
      creds[:amqp] = {:userid => "amqp_user", :password => "amqp_password"}
      @ems.update_authentication(creds, :save => false)
      @ems.verify_credentials(:amqp).should be_true
    end

    it "indicates that an event monitor is available" do
      OpenstackEventMonitor.stub(:available?).and_return(true)
      @ems.event_monitor_available?.should be_true
    end

    it "indicates that an event monitor is not available" do
      OpenstackEventMonitor.stub(:available?).and_return(false)
      @ems.event_monitor_available?.should be_false
    end

    it "logs an error and indicates that an event monitor is not available when there's an error checking for an event monitor" do
      OpenstackEventMonitor.stub(:available?).and_raise(StandardError)
      $log.should_receive(:error).with(/Exeption trying to find openstack event monitor/)
      @ems.event_monitor_available?.should be_false
    end
  end

  context "provider_hooks" do
    before :each do
      @ems = FactoryGirl.create(:ems_openstack_infra_with_authentication)
    end

    it "creates related ProviderOpenstack after creating EmsOpenstackInfra" do
      @ems.provider.name.should eq @ems.name
      @ems.provider.zone.should == @ems.zone
      ManageIQ::Providers::Openstack::Provider.count.should eq 1
    end

    it "destroys related ProviderOpenstack after destroying EmsOpenstackInfra" do
      ManageIQ::Providers::Openstack::Provider.count.should eq 1
      @ems.destroy
      ManageIQ::Providers::Openstack::Provider.count.should eq 0
    end

    it "related EmsOpenstack nullifies relation to ProviderOpenstack on EmsOpenstackInfra destroy" do
      # add ems_cloud relation to @ems
      @ems_cloud = FactoryGirl.create(:ems_openstack_with_authentication)
      @ems.provider.cloud_ems << @ems_cloud

      # compare they both use the same provider
      @ems_cloud.provider.should == @ems.provider

      # destroy ems and see the relation of ems_cloud to provider nullified
      @ems.destroy
      ManageIQ::Providers::Openstack::Provider.count.should eq 0
      @ems_cloud.reload.provider.should be_nil
    end
  end

  context "cloud disk usage" do
    before do
      @provider = FactoryGirl.create(:provider_openstack, :name => "undercloud")
      @cloud = FactoryGirl.create(:ems_openstack, :name => "overcloud", :provider => @provider)
      @infra = FactoryGirl.create(:ems_openstack_infra_with_stack, :name => "undercloud", :provider => @provider)
      @cluster = FactoryGirl.create(:ems_cluster_openstack, :ext_management_system => @infra)
    end

    it "Block Storage / Cinder" do
      expect(@cluster.cloud_block_storage_disk_usage).to eq(0)

      @cloud.cloud_volumes << FactoryGirl.create(:cloud_volume_openstack, :size => 11, :status => "noterror")
      @cloud.cloud_volumes << FactoryGirl.create(:cloud_volume_openstack, :size => 50, :status => "error")

      expect(@cluster.cloud_block_storage_disk_usage).to eq(11)
    end

    it "Object Storage / Swift" do
      stack = FactoryGirl.create(:orchestration_stack_openstack_infra, :name => "overcloud")
      stack.parameters << FactoryGirl.create(:orchestration_stack_parameter_openstack_infra, :name => "SwiftReplicas", :value => 3)
      stack.parameters << FactoryGirl.create(:orchestration_stack_parameter_openstack_infra, :name => "ObjectStorageCount", :value => 2)
      @infra.orchestration_stacks << stack

      expect(@cluster.cloud_object_storage_disk_usage).to eq(0)

      container = FactoryGirl.create(:cloud_object_store_container, :bytes => 12)
      @cloud.cloud_object_store_containers << container

      expect(@cluster.cloud_object_storage_disk_usage).to eq(12 * 2)
    end
  end
end
