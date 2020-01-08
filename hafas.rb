require "faraday"
require "json"

module Hafas

  class Station

    class Coordinates

      @@inst_vars = %w(x y layerX crdSysX)

      def initialize(obj)

        @@inst_vars.each do |var|
          instance_variable_set((?@+var).to_sym, obj[var])
        end

      end

      attr_reader *@@inst_vars.map(&:to_sym)

    end

    @@inst_vars = %w(lid type name icoX extId state crd meta pCls wt)

    def initialize(json)

      @@inst_vars.each do |var|
        if var == "crd"
          instance_variable_set((?@+var).to_sym, Coordinates.new(json[var]))
        else
          instance_variable_set((?@+var).to_sym, json[var])
        end
      end

    end

    attr_reader *@@inst_vars.map(&:to_sym)

  end

  class Api

    def initialize(cli=false)

      # The ID doesn't seem to matter at any point.
      # It's just used for identifying the current browser session. It can
      # be any, and I mean ANY String, as long as it is 16 characters long
      # and filled with characters from the charset [a-z0-9].

      @req_id = genid
      @cli = cli
      @@first_nasa_warn = true

    end

    def search(place, *opts)

      resp = Faraday.post("https://reiseauskunft.insa.de/bin/mgate.exe") do |req|

        # get milliseconds timestamp
        req.params["rnd"] = getrnd

        # this is firefox!
        req.headers["User-Agent"] = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:71.0) Gecko/20100101 Firefox/71.0"

        # trust us, we are coming from reiseauskunft.insa.de
        req.headers["Referrer"] = "https://reiseauskunft.insa.de/auskunft/"
        req.headers["Origin"] = "https://reiseauskunft.insa.de"
        req.headers["Host"] = "reiseauskunft.insa.de"

        # not trusting us yet? here's our auth
        req.body = {"id":@req_id,"ver":"1.20","lang":"deu","auth":{"type":"AID","aid":"hf7mcf9bv3nv8g5f"},"client":{"id":"NASA","type":"WEB","name":"webapp","l":"vs_webapp_nasa"},"formatted":false,"svcReqL":[{"meth":"LocMatch","req":{"input":{"field":"S","loc":{"name":place+??,"type":"ALL","dist":1000},"maxLoc":7}}}]}.to_json

        # we want a json
        req.headers["Content-Type"] = "application/json"

      end

      if resp.status == 200

        #TODO convert to Hafas::Station

        result = JSON.parse resp.body.force_encoding "UTF-8"

        result = result["svcResL"][0]["res"]["match"]["locL"].map { |station| ::Hafas::Station.new(station) }

        if opts.include?(:NO_AMBIGUITY)

          case result.length <=> 1
          when -1
            abort "Nothing could be found for '#{place}'."
          when 0
            result[0]
          when 1

            print "The name '#{place}' is ambiguous. If your station appears in the following list, "

            if @cli
              stc = 0
              puts "please type the corresponding number(or press Return to exit)."
              puts
              puts result.map{ |s| stc+=1; "#{"%#{result.length.to_s.length}i"%stc}) #{s.name}" }
            else
              puts "please specify it by its ID instead."
              puts
              puts result.map{ |s| "#{s.name} (#{s.extId ? "ID #{s.extId}" : "no ID"})" }
            end

            puts

            if @cli

              print "Number? "
              number = gets.chomp.to_i

              if number == 0
                abort "This tool uses NASA, the local transport service of the German state of Saxony-Anhalt.\nIf you are looking for a local transport stop in a different region of Germany that is not a train station, it probably won't appear here."
              end

              return result[number - 1]

            else

              abort "This tool uses NASA, the local transport service of the German state of Saxony-Anhalt.\nIf you are looking for a local transport stop in a different region of Germany that is not a train station, it probably won't appear here."

            end

          end

        end

      else

        raise "HAFAS API responded with HTTP #{resp.status}"

      end

    end

    private


    def genid
      # generates the id that will be used by the class instance for requests
      Array.new(16){((?a..?z).to_a+(0..9).to_a).sample}.join
    end

    def getrnd
      # generate the rnd timestamp.... whatever that's for
      (Time.now.to_f * 1000).to_i.to_s
    end

  end

end
