require 'ptools'
require 'yaml'

require_relative 'version'

DEFAULT_IGNORES = %w(
  tmp
  .hg
  .svn
  .git
  .gitignore
  node_modules
  bower_components
  target
  dist
  .vagrant
  Gemfile.lock
  *.exe
  *.bin
  *.apk
  *.ap_
  res
  *.dmg
  *.pkg
  *.app
  *.xcodeproj
  *.lproj
  *.xcassets
  *.pmdoc
  *.dSYM
  *.class
  *.zip
  *.jar
  *.war
  *.xpi
  *.jad
  *.cmo
  *.cmi
  *.pdf
  *.dot
  *.png
  *.gif
  *.jpg
  *.jpeg
  *.tiff
  *.ico
  *.wav
  *.mp3
)

#
# Note that order is significant;
# Only the earliest file pattern match's rule applies.
#
DEFAULT_RULES = [
  ['*.{reg,bat,ps1}', /(ascii|utf-16)/],
  ['*', /(utf-8|ascii|binary|unknown)/]
]

DEFAULT_CONFIGURATION = {
  'rules' => DEFAULT_RULES
}

# Warning for files that do not exist
NO_SUCH_FILE = 'no such file'

MAC_OS_X = RUBY_PLATFORM =~ /darwin/

MIME_FLAG =
  if MAC_OS_X
    '--mime-encoding'
  else
    '-i'
  end

PARSER =
  if MAC_OS_X
    /^(.+)\:\s+(.+)$/
  else
    /^.+\:\s+(.+);\s+charset=(.+)$/
  end

DNE =
  if MAC_OS_X
    /^.+: cannot open `.+' (No such file or directory)$/
  else
    /ERROR\:/
  end

#
# Parse, model, and print an encoding.
# Distinct from Ruby's built-in Encoding class.
#
class AnEncoding
  attr_accessor :filename, :empty, :encoding

  def self.parse(filename, file_line)
    if file_line =~ DNE
      AnEncoding.new(filename, false, NO_SUCH_FILE)
    else
      match = file_line.match(PARSER)

      empty = match[1] == 'inode/x-empty' || match[2] == 'binary'
      encoding = match[2]

      AnEncoding.new(filename, empty, encoding)
    end
  end

  def initialize(filename, empty, encoding)
    @filename = filename
    @empty = empty
    @encoding = encoding
  end

  def violate?(rules)
    # Ignore empty files, which are considered binary.
    if @empty
      false
    else
      preferred = rules.select do |rule|
        Dotsmack::fnmatch?(rule.first, filename)
      end.first[1]

      if ! (encoding =~ preferred)
        [encoding, preferred]
      else
        false
      end
    end
  end

  def to_s(encoding_difference = false)
    if encoding_difference
      observed = encoding_difference[0]
      preferred = encoding_difference[1].inspect

      if observed == NO_SUCH_FILE
        "#{@filename}: #{NO_SUCH_FILE}"
      else
        "#{@filename}: observed #{observed} preferred: #{preferred}"
      end
    else
      "#{@filename}: #{@encoding}"
    end
  end

  def to_finding(encoding_difference = false)
    if encoding_difference
      observed = encoding_difference[0]
      preferred = encoding_difference[1].inspect

      if observed == NO_SUCH_FILE
        finding = StatModule::Finding.new(false, 'File does not exist', "#{@filename}: #{NO_SUCH_FILE}")
      else
        finding = StatModule::Finding.new(true, 'File encoding', "Observed #{observed}")
        finding.categories = ['Compatibility']
        finding.location = StatModule::Location.new(@filename.to_s)
        finding.recommendation = "Prefered #{preferred}"
      end
      finding
    end
  end
end

def self.check(filename, configuration = nil, is_stat = false)
  configuration =
    if configuration.nil?
      DEFAULT_CONFIGURATION
    else
      DEFAULT_CONFIGURATION.merge(YAML.load(configuration))
    end

  rules = configuration['rules']

  line = `file #{MIME_FLAG} "#{filename}" 2>&1`

  encoding = AnEncoding.parse(filename, line)

  encoding_difference = encoding.violate?(rules)

  if is_stat
    yield encoding.to_finding(encoding_difference) if encoding_difference
  else
    puts encoding.to_s(encoding_difference) if encoding_difference
  end
end
