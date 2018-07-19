## Uncomment and set this to only include directories you want to watch
# directories %w(app lib config test spec features) \
#  .select{|d| Dir.exists?(d) ? d : UI.warning("Directory #{d} does not exist")}

guard :shell do
  watch(%r{^([^/]+).lua$}) do |m|
    `busted spec/#{m[1]}_spec.lua`
  end
  watch(%r{^([^/]+)/([^/]+).lua$}) do |m|
    `busted spec/#{m[2]}_spec.lua`
  end
 
  watch(%r{^(spec/.+.lua)$}) do |m|
    `busted #{m[1]}`
  end
end

#vi filetype=ruby
