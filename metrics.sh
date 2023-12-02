#! /usr/bin/env bash

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
per_page=100
echo "Fetching PRs for ${OWNER}/${REPO}"
response=$(gh api -H "Accept: application/vnd.github+json" --method GET /repos/${OWNER}/${REPO}/pulls -f state=closed -F per_page=$per_page)
pr_count=$(jq length <<< $response)
echo "Fetched ${pr_count} PRs"

# Step 3: fetch reviews per PR & compile data
durations=( )
review_latencies=( )
review_counts=( )

for pr in $(echo $response | jq -c '.[] | { number: .number, created_at: .created_at, merged_at: .merged_at }') # Use jq to parse the JSON response into an array
do
  number=$(echo "$pr" | jq -r .number)
  created_at=$(echo "$pr" | jq -r .created_at)
  merged_at=$(echo "$pr" | jq -r .merged_at)

  if [ $merged_at == 'null' ]; then
    echo "PR $number was not been merged; skipping."
    break
  fi

  duration=$(( $(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${merged_at}" +%s) - $(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${created_at}" +%s) ))
  durations+=( $duration )

  review_response=$(gh api -H "Accept: application/vnd.github+json" --method GET /repos/${OWNER}/${REPO}/pulls/${number}/reviews)

  first_reviewed_at=$(echo $review_response | jq -r '.[-1].submitted_at')
  review_latency=$(( $(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${first_reviewed_at}" +%s) - $(date -j -f "%Y-%m-%dT%H:%M:%SZ" "${created_at}" +%s) ))
  review_latencies+=( $review_latency )

  review_count=$(jq length <<< $review_response)
  review_counts+=( $review_count )
done

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