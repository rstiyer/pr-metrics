# pr-metrics
Reports metrics about pull requests, including review latency, among your available repositories

## How to use

### Prerequisites

Before you can use `./metrics.sh` script, ensure the following CLI tools are installed:
* [`gh`](https://cli.github.com/)
* [`jq`](https://jqlang.github.io/jq/)
* [`datamash`](https://www.gnu.org/software/datamash/)

### Basic usage
```
./metrics.sh <owner> <repository>
```
### Available options

| Flag  | Type | Description | Default |
| ------------- | ------------- | ------------- | ------------- |
| `-d`  | `Date`  | The earliest date to include in result resultations. PRs merged before this date will be included | `2023-6-30T11:59:59Z`
| `-n`  | `number`  | The maximum number of PRs to include in result resultations. The most-recent `n` will be included. | `1000`

> [!NOTE]
> These options are not mutually exclusive! The tool stops as soon as _either_ criteria is met.
