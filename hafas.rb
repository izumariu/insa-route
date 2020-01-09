require "faraday"
require "json"
require "time"

class Object
  def if_nil(obj)
    self != nil ? self : obj
  end
end

class String
  def underline(char)
    if char.length != 1
      raise ArgumentError, "Argument of #underline may only be one character long"
    end
    [self, char * self.length].join(?\n)
  end
end

module Hafas

  class Connection

    class Partial

      def initialize(partialObj)

        @data = partialObj.split(?$)
        [0,1].each { |i| @data[i] = @data[i].split(?@).map{ |pair| pair.split(?=) }.to_h }

      end

      attr_reader :data

      def [](i)
        @data[i]
      end

    end

    @@inst_vars = %w(cid date dur chg dep arr secL freq msgL conSubscr recState cksum cksumDti sDays ctxRecon)

    def initialize(connObj)

      @json = connObj
      @@inst_vars.each { |var| instance_variable_set((?@+var).to_sym, connObj[var]) }

    end

    attr_reader *@@inst_vars[0..-2]

    def prettify

      partials = @ctxRecon.match(/^[^\$]+\$(.+)$/)[1].split("$§T$").map{ |i| Partial.new(i) }

      partials.map do |partial|

        out = []

        duration_s = Time.parse(partial[3]).to_i - Time.parse(partial[2]).to_i
        duration_m = (duration_s / 60) % 60
        duration_h = duration_s / 60 / 60
        mot = partial[4].strip.split(/\s+/).map(&:strip).join(" ")
        dep_p = "#{partial[0]["O"]}"
        arr_p = "#{partial[1]["O"]}"
        dep_t = "#{partial[2][8,2]}:#{partial[2][10,2]}"
        arr_t = "#{partial[3][8,2]}:#{partial[3][10,2]}"

        out.push "O #{dep_t} #{dep_p}"
        out.push "| #{mot}"                       # TODO add destination
        out.push "| #{duration_h}h#{duration_m}m" # TODO add stop count
        out.push "| "                             # TODO alternatives
        out.push "O #{arr_t} #{arr_p}"

        out.join ?\n

      end.join("\n\n")

    end

    def inspect
      "#<Hafas::Connection #{@@inst_vars.map{ |var| _var_val=instance_variable_get((?@+var).to_sym); "#{var}=#{_var_val.is_a?(Hash)||_var_val.is_a?(Array) ? "{...}" : _var_val.inspect}" }.select{|i|i!=nil}.join(" ")}>"
    end

    def to_json
      @json
    end

    def recon
      @ctxRecon
    end

  end

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

      @json = json

      @@inst_vars.each do |var|
        if var == "crd"
          instance_variable_set((?@+var).to_sym, Coordinates.new(json[var]))
        else
          instance_variable_set((?@+var).to_sym, json[var])
        end
      end

    end

    def to_json
      @json
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

      result = mgate(
        {
          "id": @req_id,
          "ver": "1.20",
          "lang": "eng",
          "auth": {
            "type": "AID",
            "aid": "hf7mcf9bv3nv8g5f"
          },
          "client": {
            "id": "NASA",
            "type": "WEB",
            "name": "webapp",
            "l": "vs_webapp_nasa"
          },
          "formatted": false,
          "svcReqL": [
            {
              "meth": "LocMatch",
              "req": {
                "input": {
                  "field": "S",
                  "loc": {
                    "name": place+??,
                    "type": "ALL",
                    "dist": 1000
                  },
                  "maxLoc": 7
                }
              }
            }
          ]
        }
      )

      result = result["svcResL"][0]["res"]["match"]["locL"].map{ |station| ::Hafas::Station.new(station) }.select{ |station| /#{place.split(/[ .,:;]/).join("")}/i.match station.name }

      if opts.include?(:NO_AMBIGUITY)

        case result.length <=> 1
        when -1
          puts "Nothing could be found for '#{place}'."
          abort "This tool uses NASA, the local transport service of the German state of Saxony-Anhalt. If you are looking for a local transport stop in a different region of Germany that is not a train station, it probably won't appear here."
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

    end

    def routes(from, to, *opts)
      # opts(all optional!):
      # :time => Unix timestamp
      # :timeIsDeparture => boolean, signalizes
      #                     whether :time is departure or arrival
      # :via => Array of stations

      opts = opts[0]

      opts[:time] ||= Time.now.to_i

      # TODO
      mgate(
        {
          "id":@req_id,
          "ver":"1.20",
          "lang":"eng",
          "auth":
          {
            "type":"AID",
            "aid":"hf7mcf9bv3nv8g5f"
          },
          "client":
          {
            "id":"NASA",
            "type":"WEB",
            "name":"webapp",
            "l":"vs_webapp_nasa"
          },
          "formatted":false,
          "svcReqL":
          [
            {
              "meth":"TripSearch",
              "req":
              {
                "depLocL":[from.to_json],                         # departure station
                "arrLocL":[to.to_json],                           # arrival station
                "viaLocL":(opts[:via].if_nil([])).map(&:to_json), # go via these stations
                "minChgTime":"-1",                                # minimum change time
                "maxChg":"1000",                                  # maximum amount of changes
                "liveSearch":false,
                "jnyFltrL":
                [
                  {
                    "type":"PROD",
                    "mode":"INC",
                    "value":1023,
                    "locIdx":0
                  },
                  {
                    "type":"PROD",
                    "mode":"INC",
                    "value":1023,
                    "locIdx":1
                  }
                ],
                "gisFltrL":
                [
                  {
                    "type":"P",
                    "mode":"FB",
                    "profile":
                    {
                      "type":"F",
                      "enabled":true,
                      "maxdist":"2000"
                    }
                  },
                  {
                    "type":"M",
                    "mode":"FB",
                    "meta":"foot_speed_normal"
                  },
                  {
                    "type":"P",
                    "mode":"FB",
                    "profile":
                    {
                      "type":"B",
                      "enabled":false,
                      "maxdist":"0"
                    }
                  },
                  {
                    "type":"M",
                    "mode":"FB",
                    "meta":"bike_speed_normal"
                  },
                  {
                    "type":"P",
                    "mode":"FB",
                    "profile":
                    {
                      "type":"K",
                      "enabled":false,
                      "maxdist":"0"
                    }
                  },
                  {
                    "type":"M",
                    "mode":"FB",
                    "meta":"car_speed_normal"
                  }
                ],
                "getPolyline":true,

                # specify the time in military time format
                "outTime":Time.at(opts[:time]).strftime("%H%M%S"), # format HMS
                "outDate":Time.at(opts[:time]).strftime("%Y%m%d"), # format Ymd

                # outFwrd ? time=time_of_departure : time=time_of_arrival
                "outFrwd": opts[:timeIsDeparture].if_nil(true),

                "ushrp":true,
                "getPasslist":true,
                "getTariff":true
              },
              # somehow in requests the second number increments when a station
              # is changed, so they kind of are route ids?
              # TODO figure out wtf dis is
              "id":"1|3|"
            }
          ]
        }
      )["svcResL"][0]["res"]["outConL"].map{ |conn| ::Hafas::Connection.new(conn) }

    end

    private

    def mgate(body)

      body.is_a?(Hash)||raise(ArgumentError)

      resp = Faraday.post("https://reiseauskunft.insa.de/bin/mgate.exe") do |req|

        # get milliseconds timestamp
        req.params["rnd"] = getrnd

        # this is firefox!
        req.headers["User-Agent"] = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:71.0) Gecko/20100101 Firefox/71.0"

        # trust us, we are coming from reiseauskunft.insa.de
        req.headers["Referrer"] = "https://reiseauskunft.insa.de/auskunft/"
        req.headers["Origin"] = "https://reiseauskunft.insa.de"
        req.headers["Host"] = "reiseauskunft.insa.de"

        # we want a json
        req.headers["Content-Type"] = "application/json"

        req.body = body.to_json

      end

      if resp.status != 200
        raise "mgate returned HTTP #{resp.status}"
      end

      JSON.parse resp.body.force_encoding "UTF-8"

    end

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
