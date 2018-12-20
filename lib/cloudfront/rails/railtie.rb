module Cloudfront
  module Rails
    class Railtie < ::Rails::Railtie

      module CheckTrustedProxies
        def trusted_proxy?(ip)
          ::Rails.application.config.cloudfront.ips.any?{ |proxy| proxy === ip rescue false} || super
        end

        def strip_port(ip_address)
          # Stolen outright from Rack 2.1.0
          # IPv6 format with optional port: "[2001:db8:cafe::17]:47011"
          # returns: "2001:db8:cafe::17"
          return ip_address.gsub(/(^\[|\]:\d+$)/, '') if ip_address.include?('[')

          # IPv4 format with optional port: "192.0.2.43:47011"
          # returns: "192.0.2.43"
          return ip_address.gsub(/:\d+$/, '') if ip_address.count(':') == 1

          ip_address
        end

        def split_ip_addresses(ip_addresses)
          # throw out port numbers so this is semi-compliant with https://tools.ietf.org/html/rfc7239
          super(ip_addresses).map { |ip_string| strip_port(ip_string) }
        end
      end

      Rack::Request.prepend CheckTrustedProxies

      module RemoteIpProxies
        def proxies
          super + ::Rails.application.config.cloudfront.ips
        end
      end

      ActionDispatch::RemoteIp.prepend RemoteIpProxies

      CLOUDFRONT_DEFAULTS = {
        expires_in: 12.hours,
        timeout: 5.seconds,
        ips: Array.new
      }

      config.before_configuration do |app|
        app.config.cloudfront = ActiveSupport::OrderedOptions.new
        app.config.cloudfront.reverse_merge! CLOUDFRONT_DEFAULTS
      end

      config.after_initialize do |app|
        begin
          ::Rails.application.config.cloudfront.ips += Importer.fetch_with_cache
        rescue Importer::ResponseError => e
          ::Rails.logger.error "Cloudfront::Rails: Couldn't import from Cloudfront: #{e.response}"
        rescue => e
          ::Rails.logger.error "Cloudfront::Rails: Got exception: #{e}"
        end
      end

    end
  end
end
