module VCenterDriver
    class VcImporter
        attr_accessor :list

        ##################
        # Constructors
        ##################
        def initialize(one_client, vi_client)
            @vi_client  = vi_client
            @one_client = one_client

            @list = {}
            @info = {}
            @info[:clusters] = {}
            @out = []
        end

        def self.new_child(one_client, vi_client, type)
            case type
            when "datastores"
                VCenterDriver::DsImporter.new(one_client, vi_client)
            else
                raise "unknown object type"
            end
        end

        def one_str
            return @one_class.to_s.split('::').last if @one_class

            "OpenNebula object"
        end

        def stdout
            @out.each do |msg|
                puts msg
                puts
            end
        end

        def output
            @out
        end

        def process_import(indexes, opts = {})
            raise "the list is empty" if list_empty?
            indexes = indexes.gsub(/\s+/, "").split(",")

            indexes.each do |index|
                begin
                    @info[index] = {}
                    @info[index][:opts] = opts[index]

                    # select object from importer mem
                    selected = get_element(index)

                    id = import(selected)

                    @out << "Success: #{one_str} with id #{id} created!"
                rescue Exception => e
                    @out << "Error: Couldn't import #{index} due to #{e.message}!"
                    manage_error
                end
            end
        end


        protected

        ########################################
        # ABSTRACT INTERFACE
        ########################################

        MESS = "missing method from parent"

        def get_list;    raise MESS end
        def add_cluster(cid, eid) raise MESS end
        def remove_default(id) raise MESS end
        def import(selected) raise MESS end

        ########################################

        def create(info, &block)
            resource = VCenterDriver::VIHelper.new_one_item(@one_class)
            message = "Error creating the OpenNebula resource"

            rc = resource.allocate(info)
            VCenterDriver::VIHelper.check_error(rc, message)

            rc = block.call(resource)
        end

        def list_empty?
            @list == {}
        end

        def get_element(ref)
            raise "the list is empty" if list_empty?

            return @list[ref] if @list[ref]

            raise "#{ref} not found!"
        end

        def add_clusters(one_id, clusters, &block)
            clusters.each do |cid|
                @info[:clusters][cid] ||= VCenterDriver::VIHelper.one_item(OpenNebula::Cluster, cid.to_s, false)
                rc =  add_cluster(cid.to_i, one_id.to_i)
                VCenterDriver::VIHelper.check_error(rc, "add element to cluster")
            end
            remove_default(one_id)
        end
    end

    private

    def manage_error
        #this will manage the error
    end
end
