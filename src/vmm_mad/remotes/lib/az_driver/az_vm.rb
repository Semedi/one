module AzDriver
    class VirtualMachine

        attr_accessor :az_item
        attr_accessor :name

        ATTRS = {
            AZ_DISK: :diskname
        }


        def initialize(opts = {})
            @group_name = opts[:gname]
            @name = opts[:name]

            @client = opts[:client].compute || opts[:client] || nil
            @az_item = opts[:az_item] || nil
            @one = {}
        end

        def get(expand = nil)
            @az_item = @client.virtual_machines.get(@group_name, @name , expand)
        end

        def failed?()
            if @az_item
                @az_item.provisioning_state == "Failed"
            end
        end

        def size()
            if @az_item
                @az_item.hardware_profile.vm_size
            end
        end

        def diskname()
            if @az_item
                os_disk = @az_item.storage_profile.os_disk.name
            end
        end

        def nics()
            if @az_item
                @az_item.network_profile.network_interfaces.map do |nic|
                    nic.id.split("/").last
                end
            end
        end

		def print()
            AzDriver::Helper.print_item(@az_item)
		end

        def set_resources(cpu, mem)
            @one[:hw] = {
                cpu: cpu,
                mem: mem
            }
        end

        def delete_disk(name)
            @client.disks.delete(@group_name, name)

        end

        def used_resources()
            @one[:hw] unless @one[:hw].nil?
        end

        def status
            @status unless @status.nil?
        end

        def info()
            view = @client.virtual_machines.instance_view(@group_name, @name)
            @status = view.statuses[1]
        end

        def start()
            @client.virtual_machines.start(@group_name, @name)
        end

        def stop()
            @client.virtual_machines.power_off(@group_name, @name)
        end

        def poweroff()
            @client.virtual_machines.deallocate(@group_name, @name)
        end

        def delete()
            @client.virtual_machines.delete(@group_name, @name)
        end
    end
end
