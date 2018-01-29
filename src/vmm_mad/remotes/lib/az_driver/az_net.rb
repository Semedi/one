module AzDriver
    class Network
        attr_accessor :az_item

        def initialize(opts = {})
            @group_name = opts[:gname]
            @client = opts[:client].network || opts[:client] || nil
            @az_item = opts[:az_item] || nil
            @nics = {}
        end

        def subnets
            if @az_item
                @az_item.subnets
            end
        end

        def delete_nic(nic_name)
            @client.network_interfaces.delete(@group_name, nic_name)
        end

        def retrieve_nics(vm)
            if @nics[vm]
                @nics[vm]
            end
        end

        def create_nic(nic_name)

            location = @az_item.location
            model = AzDriver::Client::NetworkModels
            nic = @client.network_interfaces.create_or_update(
                @group_name,
                nic_name,
                model::NetworkInterface.new.tap do |interface|
                    interface.location = location
                    interface.ip_configurations = [
                        model::NetworkInterfaceIPConfiguration.new.tap do |nic_conf|
                            nic_conf.name = nic_name
                            nic_conf.private_ipallocation_method = model::IPAllocationMethod::Dynamic
                            nic_conf.subnet = az_item.subnets.first
                        end
                    ]
                end
            )
        end
    end
end
