#!/usr/bin/env zsh
# Parses the Rime data files the app ships.
#
# librime reads these at deployment time, not at build time. A malformed schema
# therefore produces a keyboard that silently falls back to the ten-word
# prototype engine on a real device, with nothing failing anywhere earlier. This
# is the only place that reads them before a user does.
#
# Uses the Ruby that ships with macOS, so there is nothing to install.
set -euo pipefail

ROOT=${0:A:h:h}
DATA="$ROOT/iOS/RimeData"

if [[ ! -d "$DATA" ]]; then
  print -u2 "Rime data directory not found: $DATA"
  exit 1
fi

for file in "$DATA"/*.yaml; do
  print "Parsing ${file:t}"
  ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$file"
done

# The punctuator is what makes Chinese punctuation come out full-width. It is
# defined inline rather than imported from a preset, so a missing section means
# the keyboard types half-width punctuation with no other symptom.
ruby -ryaml -e '
schema = YAML.load_file(ARGV[0])
processors = schema.dig("engine", "processors") || []
abort "vibe_pinyin.schema.yaml: punctuator is not in engine/processors" \
  unless processors.include?("punctuator")
abort "vibe_pinyin.schema.yaml: punctuator must run after speller" \
  unless processors.index("punctuator") > processors.index("speller")

shapes = schema.dig("punctuator", "half_shape")
abort "vibe_pinyin.schema.yaml: punctuator/half_shape is missing" \
  if shapes.nil? || shapes.empty?

%w[, . ? ! : ;].each do |key|
  abort "vibe_pinyin.schema.yaml: punctuator/half_shape has no entry for #{key}" \
    unless shapes.key?(key)
end

print "punctuator maps #{shapes.size} keys\n"
' "$DATA/vibe_pinyin.schema.yaml"

print "Rime data OK"
