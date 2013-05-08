class HomeController < ApplicationController
  def index
		#@neo = Neography::Rest.new							# refrence to neo4j graph
		@neo = Neography::Rest.new(ENV['NEO4J_URL'] || "http://localhost:7474")
		@neo.set_node_auto_index_status(true)
		@neo.set_relationship_auto_index_status(true)				# setting auto indexing true
		@neo.add_node_auto_index_property("name")			# setting auto indexing on property "name" and "activity" because later we will do query to neo4j using these two properties
		@neo.add_node_auto_index_property("activity")
		#geoloc=Geokit::Geocoders::YahooGeocoder.geocode '140 Market St, San Francisco, CA'
		#geoloc=Geokit::Geocoders::MultiGeocoder.geocode('140 Market St, San Francisco, CA')
		#@x = Geocoder.coordinates("Bonhoefferstrasse 13, Heidelberg, Germany")
		#@result = request.location
		# Get all activity available in Neo4j to fill selection box in User View
		@activity_array = @neo.execute_query("start n=node(*) where has(n.activity) return n.activity")["data"].map{|a| a.first}.to_s.delete('[]"').split(', ').collect! {|n| n}
		# Get all locations available in Neo4j to fill selection box in User View
		@location_array = @neo.execute_query("start n=node(*) where has(n.name) return n.name")["data"].map{|a| a.first}.to_s.delete('[]"').split(', ').collect! {|n| n}
		# storing values of to and from parameters if they exist in request
		from = params[:from] if params.has_key?(:from) 
		to = params[:to] if params.has_key?(:to)
		# store search type which will be used to decide if user want to search on based on activity or locatin
		search_type = params[:search_type] if params.has_key?(:search_type)	
		
		if params.has_key?(:from)				#If from parameter selected
			@from = from
			@to = to
			result_hash = Hash.new
			node1 = @neo.get_node_auto_index("name", from)
			node1_id = node1.to_s.split('node/').last.split('/').first.to_i
			if search_type == "activity"		# if search type is 'activity', Graph is queried on activity property
				activity = params[:activity]
				node2_id = @neo.execute_query("START n=node(*) WHERE {activity} IN n.activity! RETURN ID(n)",{:activity => activity})["data"].to_s.delete('[').delete(']').to_i
				@activity = activity
			else								# else 	Graph is queried on location name property
				node2 = @neo.get_node_auto_index("name", to)
				node2_id = node2.to_s.split('node/').last.split('/').first.to_i
			end
			
			if (node1_id != node2_id)	# path search only happens is source and destination node id's are different
				n1 = @neo.execute_query("start n=node({node1_id}),m=node({node2_id}) match p= allShortestPaths(n-[?*]->m) return extract (m in nodes(p): ID(m)) as route LIMIT 1",{:node1_id => node1_id,:node2_id => node2_id})["data"]
				n2 = @neo.execute_query("start n=node({node1_id}),m=node({node2_id}) match p= allShortestPaths(n-[?*]->m) return extract (m in rels(p): m.time) as tmt LIMIT 1",{:node1_id => node1_id,:node2_id => node2_id})["data"]
				
				node_array = n1.map{|a| a.first}.to_s.delete('[').delete(']').split(',').collect! {|n| n.to_i}  #store all nodes of path in array
				time_array = n2.map{|a| a.first}.to_s.delete('[').delete(']').split(',').collect! {|n| n.to_i}	#store time of each part of path in array
				
				# Calculate total time of journey
				sum = 0
				time_array.each { |a| sum+=a }
				@sum = sum
				
				@time_array = time_array
				actionCheck_array = Array.new		# initilize a new array to combine similar continous actions eg. if keep straight comes twice or thrice back to back it have to be one one action with time of all three actions
				
				counter = 0 # set counter to start loop for rendring the path
				while counter <= (node_array.length - 1)  do
					case counter
						when 0  				; 	node1_id = node_array[counter]
													node2_id = node_array[counter + 1]
													direction = @neo.execute_query("start n=node({node1_id}),m=node({node2_id}) match n-[r]->m return r.direction",{:node1_id => node1_id,:node2_id => node2_id})["data"]
													direction = direction.to_s.delete('[').delete(']').delete('"')
													result_hash["Head #{direction} from #{from}"] = time_array[counter]
													#actionCheck_array.push("Head #{direction} from start position")
						
						when (node_array.length - 1)   ; 	#actionCheck_array.push("Your destination will be in front of you")
						
						else					; 	
													 
													# fetch names of previous, intersection and next points names from graph
													node1name = @neo.get_node_properties(@neo.get_node(node_array[counter - 1]), "name")["name"]
													node2name = @neo.get_node_properties(@neo.get_node(node_array[counter]), "name")["name"]
													node3name = @neo.get_node_properties(@neo.get_node(node_array[counter + 1]), "name")["name"]
													# Remove spaces from node names and form property name from concatination of them 
													propertyname = node1name.to_s.delete(' ') + '_'+ node2name.to_s.delete(' ') + '_' + node3name.to_s.delete(' ')
													propvalue = @neo.get_node_properties(@neo.get_node(node_array[counter]), propertyname)[propertyname]
													propvalue = propvalue.to_s.delete('[').delete(']').delete('"')
													actionCheck_array.push("#{propvalue}")
													c = counter - 1
													test_string = "#{propvalue}" + "#{c}"
													# code to update the previous value with the key already exists
													if result_hash.has_key?("#{propvalue}") and actionCheck_array.include? test_string
														last_value = result_hash.fetch("#{propvalue}").to_i
														new_value = last_value + time_array[counter]
														result_hash["#{propvalue}"] = new_value
														actionCheck_array.push("#{propvalue}" + "#{counter}")
													else
														result_hash["#{propvalue}"] = time_array[counter]
														actionCheck_array.push("#{propvalue}" + "#{counter}")	
													end
													
					end
					counter +=1
				end
				@result_hash = result_hash
			else		# else display message that source and destination location are same
				@s_d_same = "Your Current location and Destination Location are same"
			end
		end
  end
end
