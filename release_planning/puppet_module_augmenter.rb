class PuppetModuleAugmenter
  def augment!(puppet_modules)
    puppet_modules.each do |puppet_module|
      uri = URI.parse("https://forgeapi.puppetlabs.com/v3/modules/#{puppet_module.name}")
      request =  Net::HTTP::Get.new(uri.path)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE) do |http| # pay attention to use_ssl if you need it
        http.request(request)
      end
      output = response.body
      parsed = JSON.parse(output)
      begin
        puppet_module.downloads = parsed['current_release']['downloads']
        puts puppet_module.downloads
      rescue NoMethodError
        puts "Error number of downloads #{puppet_module.name}"
      end
    end
  end
end

