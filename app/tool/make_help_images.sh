#!/usr/bin/env bash
set -euo pipefail

# Run from any directory. --render-only reuses shots and ru.pdf/en.pdf.
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
pdf_dir=
if (( $# == 2 )) && [[ $1 == --render-only ]]; then
  pdf_dir=$(cd -- "$2" && pwd)
elif (( $# != 0 )); then
  printf 'Usage: %s [--render-only PDF_DIRECTORY]\n' "$0" >&2
  exit 2
fi
cd "$root"
mkdir -p .work
scratch=$(mktemp -d "$root/.work/help-images.XXXXXXXX")
trap 'rm -rf -- "$scratch"' EXIT
export TMPDIR="$scratch"

if [[ -z $pdf_dir ]]; then
  pdf_dir=$scratch
  (
    cd app
    ../.work/flutter/bin/flutter test --no-pub --update-goldens tool/screenshots_test.dart
    GUIDE_PDF_DIR="$pdf_dir" ../.work/flutter/bin/flutter test --no-pub tool/guide_pdf.dart
  )
fi

orange='#E8590C'
font="$root/app/assets/fonts/NotoSans-Bold.ttf"
ids=(
  home drawer language_dialog theme_dialog merge_files_empty merge_files_two
  merge_rules merge_progress merge_done export_overview export_format
  export_pdf_options updates about
)

# Reduce the palette further only when an image exceeds the size limit.
optimize() {
  local input=$1 output=$2 colors
  shift 2
  for colors in 128 96 64 48 32; do
    magick "$input" "$@" -strip +dither -colors "$colors" \
      -define png:compression-level=9 "PNG8:$scratch/optimized.png"
    if (( $(wc -c < "$scratch/optimized.png") < 150000 )); then
      mv -- "$scratch/optimized.png" "$output"
      return
    fi
  done
  printf 'Could not fit %s under 150 KB\n' "$output" >&2
  return 1
}

annotate() {
  local input=$1 sidecar=$2 output=$3
  local width height rows n x y w h i j
  read -r width height < <(magick identify -format '%w %h\n' "$input")
  rows=$(jq -er '
    def pixel: type == "number" and . >= 0 and floor == .;
    if type == "array" and length > 0 and all(.[];
      (.n | pixel) and (.rect | type == "array" and length == 4 and all(.[]; pixel))
    ) then
      .[] | [.n, .rect[]] | @tsv
    else error("Expected numbered annotations with integer pixel rectangles") end
  ' "$sidecar")

  local -a left=() top=() right=() bottom=() badges_x=() badges_y=()
  local boxes='' arrows='' circles=''
  local -a captions=()
  local offset
  while read -r n x y w h; do
    if (( n != ${#left[@]} + 1 || x < 0 || y < 0 || w <= 0 || h <= 0 ||
          x + w > width || y + h > height )); then
      printf 'Invalid annotation in %s: %s %s %s %s %s\n' "$sidecar" "$n" "$x" "$y" "$w" "$h" >&2
      return 1
    fi
    i=$((n - 1))
    # Leave a few pixels for the stroke when the target touches the edge.
    left[i]=$((x >= 14 ? x - 10 : 4))
    top[i]=$((y >= 14 ? y - 10 : 4))
    right[i]=$((x + w + 10 < width - 4 ? x + w + 10 : width - 4))
    bottom[i]=$((y + h + 10 < height - 4 ? y + h + 10 : height - 4))
    boxes+="roundrectangle ${left[i]},${top[i]} ${right[i]},${bottom[i]} 16,16 "
    x=${left[i]}
    y=${top[i]}
    badges_x[i]=$((x < 30 ? 30 : x))
    badges_y[i]=$((y + 8 < 30 ? 30 : y + 8))
    x=${badges_x[i]}
    y=${badges_y[i]}
    circles+="circle $x,$y $((x + 28)),$y "
    printf -v offset '%+d%+d' "$((x - width / 2))" "$((y - height / 2))"
    captions+=(-annotate "$offset" "$n")
  done <<< "$rows"

  local cx cy distance dx dy tx ty sx sy bx by min_x min_y max_x max_y
  local arrowhead1 arrowhead2 contrast
  local -a arrow_left=() arrow_top=() arrow_right=() arrow_bottom=()
  for i in "${!left[@]}"; do
    cx=$(((left[i] + right[i]) / 2))
    cy=$(((top[i] + bottom[i]) / 2))
    # Try the closest margin first. Keep arrows in clear space and away from
    # other outlines and badges. Some tightly spaced controls only get a box.
    while read -r distance dx dy tx ty; do
      (( distance >= 72 )) || continue
      sx=$((tx + 64 * dx))
      sy=$((ty + 64 * dy))
      bx=$((tx + 22 * dx))
      by=$((ty + 22 * dy))
      min_x=$(((sx < tx ? sx : tx) - 14))
      min_y=$(((sy < ty ? sy : ty) - 14))
      max_x=$(((sx > tx ? sx : tx) + 14))
      max_y=$(((sy > ty ? sy : ty) + 14))
      (( min_x >= 0 && min_y >= 0 && max_x <= width && max_y <= height )) ||
        continue
      for j in "${!left[@]}"; do
        if (( min_x < badges_x[j] + 32 && max_x > badges_x[j] - 32 &&
              min_y < badges_y[j] + 32 && max_y > badges_y[j] - 32 )); then
          continue 2
        fi
        if (( i != j && min_x < right[j] + 4 && max_x > left[j] - 4 &&
              min_y < bottom[j] + 4 && max_y > top[j] - 4 )); then
          continue 2
        fi
      done
      for j in "${!arrow_left[@]}"; do
        if (( min_x < arrow_right[j] && max_x > arrow_left[j] &&
              min_y < arrow_bottom[j] && max_y > arrow_top[j] )); then
          continue 2
        fi
      done
      contrast=$(magick "$input" \
        -crop "$((max_x - min_x))x$((max_y - min_y))+$min_x+$min_y" \
        -colorspace gray -format '%[fx:standard_deviation < 0.045 ? 1 : 0]' info:)
      [[ $contrast == 1 ]] || continue
      arrowhead1="$((bx + 12 * dy)),$((by - 12 * dx))"
      arrowhead2="$((bx - 12 * dy)),$((by + 12 * dx))"
      arrow_left+=("$min_x")
      arrow_top+=("$min_y")
      arrow_right+=("$max_x")
      arrow_bottom+=("$max_y")
      arrows+="line $sx,$sy $bx,$by polygon $tx,$ty $arrowhead1 $arrowhead2 "
      break
    done < <(
      printf '%s\n' \
        "${left[i]} -1 0 ${left[i]} $cy" \
        "$((width - right[i])) 1 0 ${right[i]} $cy" \
        "${top[i]} 0 -1 $cx ${top[i]}" \
        "$((height - bottom[i])) 0 1 $cx ${bottom[i]}" |
        sort -n
    )
  done

  local -a arrow_draw=()
  if [[ -n $arrows ]]; then
    arrow_draw=(-fill "$orange" -stroke "$orange" -strokewidth 6 -draw "$arrows")
  fi
  magick "$input" \
    -fill none -stroke "$orange" -strokewidth 6 -draw "$boxes" \
    "${arrow_draw[@]}" -fill "$orange" +stroke -draw "$circles" \
    -fill white -font "$font" -pointsize 38 -gravity Center "${captions[@]}" \
    "$scratch/annotated.png"
  optimize "$scratch/annotated.png" "$output" -resize 780x
}

for lang in ru en; do
  shots="app/tool/shots/$lang"
  output="docs/user-guide/images/$lang"
  mkdir -p "$output"
  for id in "${ids[@]}"; do
    annotate "$shots/$id.png" "$shots/$id.json" "$output/$id.png"
  done
  pdftoppm -r 70 -png -f 1 -l 1 -singlefile "$pdf_dir/$lang.pdf" "$scratch/pdf_cover"
  pdftoppm -r 70 -png -f 2 -l 2 -singlefile "$pdf_dir/$lang.pdf" "$scratch/pdf_page"
  for page in pdf_cover pdf_page; do
    optimize "$scratch/$page.png" "$output/$page.png"
  done
done
