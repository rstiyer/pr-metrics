#! /usr/bin/env bash

while getopts 'd:n:' flag; do
  case "${flag}" in
    d) start_date="${OPTARG}" ;;
    n) count="${OPTARG}" ;;
  esac
done

# To check the positional arguments, remove the processed options (if present)
shift $(($OPTIND - 1))

if [ "$#" -ne 2 ]; then
  echo "Usage: metrics.sh (repo-owner) (repo-name)"
  echo "   Ex: metrics.sh NPXInnovation echo-client"
  exit 1
fi

OWNER=$1
REPO=$2

# Step 0: check that requisite libraries are installed
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh is not installed. Please run \`brew install gh\`."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is not installed. Please run \`brew install jq\`."
  exit 1
fi

if ! command -v datamash >/dev/null 2>&1; then
  echo "Error: datamash is not installed. Please run \`brew install datamash\`."
  exit 1
fi

# Step 1: authenticate
if ! gh auth status >/dev/null 2>&1; then
  echo "Not authenticated; logging in."
  gh auth login
else
  echo "Already logged in. Skipping authentication step."
fi

# Step 2: fetch results
durations=( )
review_latencies=( )
review_counts=( )

earliest_to_include=$(date -j -f "%FT%TZ" ${start_date:-2023-6-30T11:59:59Z} +%s) # End of Q2 2023
earliest_seen=$(date +%s) # Now, to start

page=1
per_page=30
pr_count=0
skipped_count=0
cutoff=${count:-1000}

printf "\nFetching PRs for ${OWNER}/${REPO}\n"
while [ $earliest_seen -gt $earliest_to_include ] && [ $pr_count -lt $cutoff ];
do
  echo "Fetching page ${page} with page size ${per_page}"
  response=$(gh api -H "Accept: application/vnd.github+json" --method GET /repos/${OWNER}/${REPO}/pulls -f state=closed -F per_page=$per_page -F page=$page)
  echo "Fetched $(jq length <<< $response) results"

  for pr in $(echo $response | jq -c '.[] | { number: .number, created_at: .created_at, merged_at: .merged_at }') # Use jq to parse the JSON response into an array
  do
    number=$(echo "$pr" | jq -r .number)
    created_at=$(echo "$pr" | jq -r .created_at)
    merged_at=$(echo "$pr" | jq -r .merged_at)

    earliest_seen=$(date -j -f "%FT%TZ" "${created_at}" +%s)
    # TODO: Do we need to duplicate this condition?
    if [ ! $earliest_seen -gt $earliest_to_include ] || [ $pr_count -eq $cutoff ]; then
      # Stop collecting data
      break
    fi

    if [ $merged_at == 'null' ]; then
      echo "PR $number was not been merged; skipping."
      skipped_count=$(( $skipped_count + 1 ))
      continue
    fi

    pr_count=$(( $pr_count + 1 ))
    duration=$(( $(date -j -f "%FT%TZ" "${merged_at}" +%s) - $(date -j -f "%FT%TZ" "${created_at}" +%s) ))
    durations+=( $duration )

    # Step 3: fetch reviews per PR & compile data
    review_response=$(gh api -H "Accept: application/vnd.github+json" --method GET /repos/${OWNER}/${REPO}/pulls/${number}/reviews -F per_page=100)

    first_reviewed_at=$(echo $review_response | jq -r '.[-1].submitted_at')
    if [ $first_reviewed_at == 'null' ]; then
      echo "No valid review(s) found for $number; skipping."
      skipped_count=$(( $skipped_count + 1 ))
      continue
    fi
    review_latency=$(( $(date -j -f "%FT%TZ" "${first_reviewed_at}" +%s) - $(date -j -f "%FT%TZ" "${created_at}" +%s) ))
    review_latencies+=( $review_latency )

    review_count=$(jq length <<< $review_response)
    review_counts+=( $review_count )
  done

  # Increment page number after all results have been parsed
  page=$(( $page + 1 ))
done

printf "\nIncluded ${pr_count} PRs merged since $(date -j -f "%s" $earliest_seen +"%FT%TZ"); ${skipped_count} were excluded from the following metrics.\n"

# Step 4: report results
function round() {
    # $1 is expression to round (should be a valid bc expression)
    # $2 is number of decimal figures (optional). Defaults to one if none given
    local decimals=${2:-2}
    printf '%.*f\n' "$decimals" "$(bc -l <<< "a=$1; if(a>0) a+=5/10^($decimals+1) else if (a<0) a-=5/10^($decimals+1); scale=$decimals; a/1")"
}

function report_metrics() {
  results=$(printf '%s\n' $@ | datamash max 1 min 1 mean 1 median 1)

  max_seconds=$(cut -w -f 1 <<< $results)
  max_mins=$(round "${max_seconds} / 60")
  max_hours=$(round "${max_seconds} / (60 * 60)")
  echo "Maximum: $max_mins min or $max_hours hours"

  min_seconds=$(cut -w -f 2 <<< $results)
  min_mins=$(round "${min_seconds} / 60")
  min_hours=$(round "${min_seconds} / (60 * 60)")
  echo "Minimum: $min_mins min or $min_hours hours"

  mean_seconds=$(cut -w -f 3 <<< $results)
  mean_mins=$(round "${mean_seconds} / 60")
  mean_hours=$(round "${mean_seconds} / (60 * 60)")
  echo "Mean: $mean_mins min or $mean_hours hours"

  median_seconds=$(cut -w -f 4 <<< $results)
  median_mins=$(round "${median_seconds} / 60")
  median_hours=$(round "${median_seconds} / (60 * 60)")
  echo "Median: $median_mins min or $median_hours hours"
}

printf "\n-------\nRESULTS\n-------\n"

printf "\nTotal Duration\n--------------\n"
report_metrics ${durations[@]}

printf "\nFirst Review Latency\n--------------------\n"
report_metrics ${review_latencies[@]}

printf "\nReviews per PR\n--------------\n"
results=$(printf '%s\n' ${review_counts[@]} | datamash max 1 min 1 mean 1 median 1)
max=$(cut -w -f 1 <<< $results)
echo "Maximum: $max"
min=$(cut -w -f 2 <<< $results)
echo "Minimum: $min"
mean=$(cut -w -f 3 <<< $results)
echo "Mean: $mean" # TODO: round to match other values
median=$(cut -w -f 4 <<< $results)
echo "Median: $median"