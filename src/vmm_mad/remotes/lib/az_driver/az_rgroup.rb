module AzDriver
    class ResourceGroup
        attr_accessor :az_item

        # create the driver resource object
        def initialize(opts = {})
            @name   = opts[:gname]
            @client = opts[:client]
            @region = opts[:region]
            @az_item = opts[:az_item] || nil
        end

        # check if the resource group exist
        def exist?
            @client.resource.resource_groups.check_existence(@name)
        end

        # check if object exist inside the resource group
        def exist_object?(object)
            @client.resource.deployments.check_existence(@name, object)
        end

        # create the azure remote resource group
        def create()
            model = AzDriver::Client::ResourceModels
            resource_group_params = model::ResourceGroup.new.tap do |rg|
              rg.location = @region
            end

            @az_item = @client.resource.resource_groups.create_or_update(@name, resource_group_params)
        end

        # create the azure remote virtual machine
        PARAMS = ["IMAGE", "PUBLISHER", "SKU", "VM_USER", "VM_PASSWORD"]
        def create_vm(dinfo, name, nic, storage = nil)
            opts = {}
            model = AzDriver::Client::ComputeModels

            PARAMS.each do |param|
                opts[param] = dinfo.elements[param].text
            end

            vm_create_params = model::VirtualMachine.new.tap do |vm|
                vm.location = @region
                vm.os_profile = model::OSProfile.new.tap do |os_profile|
                    os_profile.computer_name = name
                    os_profile.admin_username = opts["VM_USER"]
                    os_profile.admin_password = opts["VM_PASSWORD"]
                end

                vm.storage_profile = model::StorageProfile.new.tap do |store_profile|
                    store_profile.image_reference = model::ImageReference.new.tap do |ref|
                        ref.publisher = opts["PUBLISHER"]
                        ref.offer = opts["IMAGE"]
                        ref.sku = opts["SKU"]
                        ref.version = "latest"
                    end
                end

                vm.hardware_profile = model::HardwareProfile.new.tap do |hardware|
                    hardware.vm_size = "Basic_A0"
                end

                vm.network_profile = model::NetworkProfile.new.tap do |net_profile|
                    net_profile.network_interfaces = [
                        model::NetworkInterfaceReference.new.tap do |ref|
                            ref.id = nic.id
                            ref.primary = true
                        end
                    ]
                end
            end

            vm = @client.compute.virtual_machines.create_or_update(@name, name, vm_create_params)
        end

        # create a virtual network in the resource group
        def create_net(opts = {})
            name        = opts[:name] || 'one_vnet'
            addr_prefix = opts[:addr_prefix] || '10.0.0.0/16'
            dns         = opts[:dns] || '8.8.8.8'
            subname     = opts[:subname] || 'default'
            sub_prefix  = opts[:sub_prefix] || '10.0.0.0/24'

            model = AzDriver::Client::NetworkModels
            vnet_create_params = model::VirtualNetwork.new.tap do |vnet|
                vnet.location = @region
                vnet.address_space = model::AddressSpace.new.tap do |addr_space|
                    addr_space.address_prefixes = [addr_prefix]
                end
                vnet.dhcp_options = model::DhcpOptions.new.tap do |dhcp|
                    dhcp.dns_servers = [dns]
                end
                vnet.subnets = [
                    model::Subnet.new.tap do |subnet|
                        subnet.name = subname
                        subnet.address_prefix = sub_prefix
                    end
                ]
            end

            @client.network.virtual_networks.create_or_update(@name, name, vnet_create_params)
        end

        def print_machines()
            @client.compute.virtual_machines.list(@name).each do |vm|
                puts vm.instance_view
                puts
                puts
                AzDriver::Helper.print_item(vm)
            end
        end

        def monitor_vms(host)

            # hw vars:
            totalmemory = 0
            totalcpu    = 0
            usedcpu    = 0
            usedmemory = 0

            conf = AzDriver::Config.new()

            host_obj=AzDriver.retrieve_host(host)
            capacity = host_obj.to_hash["HOST"]["TEMPLATE"]["CAPACITY"]
            if !capacity.nil? && Hash === capacity
                capacity.each{ |name, value|
                    cpu, mem = conf.instance_type_capacity(name)

                    totalmemory += mem * value.to_i
                    totalcpu    += cpu * value.to_i
                }
            else
                raise "you must define CAPACITY section properly! check the template"
            end

            host_info =  "HYPERVISOR=AZURE\n"
            host_info << "PUBLIC_CLOUD=YES\n"
            host_info << "PRIORITY=-1\n"
            host_info << "TOTALMEMORY=#{totalmemory.round}\n"
            host_info << "TOTALCPU=#{totalcpu}\n"
            host_info << "HOSTNAME=\"#{host}\"\n"

            vms_info   = "VM_POLL=YES\n"

            work_q = Queue.new
            opts_new = {
                gname: @name,
                client: @client
            }
            @client.compute.virtual_machines.list(@name).each do |vm|
                opts_new[:az_item] = vm
                opts_new[:name] = vm.name
                work_q.push AzDriver::VirtualMachine.new(opts_new)
            end
            workers = (0...10).map do
                Thread.new do
                    begin
                        while i = work_q.pop(true)

                            # monitoring vm info:
                            i.info

                            poll_data = parse_poll(i)

                            # basic vm info:
                            vm_template_to_one = AzDriver.vm_to_one(i, host, conf)
                            vm_template_to_one = Base64.encode64(vm_template_to_one)
                            vm_template_to_one = vm_template_to_one.gsub("\n","")

                            one_id = i.name.split('-').last

                            vms_info << "VM=[\n"
                            vms_info << "  ID=#{one_id || -1},\n"
                            vms_info << "  DEPLOY_ID=#{i.name},\n"
                            vms_info << "  VM_NAME=#{i.name},\n"
                            vms_info << "  IMPORT_TEMPLATE=\"#{vm_template_to_one}\",\n"
                            vms_info << "  POLL=\"#{poll_data}\" ]\n"

                            used_res = i.used_resources
                            usedcpu    += used_res[:cpu]
                            usedmemory += used_res[:mem]
                        end
                    rescue ThreadError => e
                    rescue Exception => e
                        raise e
                    end
                end
            end; "ok"
            workers.map(&:join); "ok"

            host_info << "USEDMEMORY=#{usedmemory.round}\n"
            host_info << "USEDCPU=#{usedcpu.round}\n"
            host_info << "FREEMEMORY=#{(totalmemory - usedmemory).round}\n"
            host_info << "FREECPU=#{(totalcpu - usedcpu).round}\n"

            puts host_info
            puts vms_info
        end

        def get_vm(name)
            object = @client.compute.virtual_machines.get(@name, name, 'InstanceView')
            return AzDriver::VirtualMachine.new(@client.compute, @name, object)
        end

    private
    #deallocated
    #starting

        def parse_poll(instance)
            begin
                info =  "#{AzureDriver::POLL_ATTRIBUTE[:memory]}=0 " \
                        "#{AzureDriver::POLL_ATTRIBUTE[:cpu]}=0 " \
                        "#{AzureDriver::POLL_ATTRIBUTE[:nettx]}=0 " \
                        "#{AzureDriver::POLL_ATTRIBUTE[:netrx]}=0 "

                state = ""
                if !instance
                    state = AzureDriver::VM_STATE[:deleted]
                elsif  instance.failed? || instance.status.nil?
                    state = AzureDriver::VM_STATE[:unknown]
                else
                    state = case instance.status.code.split("/").last
                    when "running", "starting"
                        AzureDriver::VM_STATE[:active]
                    when "suspended", "stopping", "stopped"
                        AzureDriver::VM_STATE[:paused]
                    when "deallocated"
                        AzureDriver::VM_STATE[:deleted]
                    else
                        AzureDriver::VM_STATE[:unknown]
                    end
                end
                info << "#{AzureDriver::POLL_ATTRIBUTE[:state]}=#{state} "

                AzDriver::VirtualMachine::ATTRS.each do |attr, function|
                    info << "#{attr.to_s.upcase}="
                    info << "\\\"#{instance.method(function).call}\\\" "
                end

                info
            rescue
                # Unknown state if exception occurs retrieving information from
                # an instance
                "#{AzureDriver::POLL_ATTRIBUTE[:state]}=#{VM_STATE[:unknown]} "
            end
        end
    end
end
