# Howdy! 

This is the github repo for the [masto.nyc](https://masto.nyc/about) v2.0 infrastructure. This is essentially what the [old kubernetes-only code](https://github.com/Five-Borough-Fedi-Project/masto.nyc) looks like now that it's migrated to Digital Ocean. It's pretty quiet here, but feel free to open an issue or reach out to @seano-vs or @jmac. We'll try and keep todo items in the issues list.

## Why Digital Ocean?

Since we came from a bare metal Kubernetes setup, we wanted to maintain as much of that infrastructure as possible- and we also wanted to follow our server principals of supporting NYC-based companies whenever possible. Luckily, Digital Ocean not only offered a k8s package but is also based out of NYC!

## Setup instructions:

Replace tofu with terraform if that's your drug of choice 🤷

1. In the DOcean console, generate a new [Personal access token](https://cloud.digitalocean.com/account/api/tokens). Put them aside for later.
2. From that page, click on the "Spaces Keys" tab and create a new set of s3 creds for the state. Put them aside for later.
3. Create a `terraform.tfvars` file. Populate it with the correct `do_token` (from step 1), `state_bucket`, and `state_key` variables.
4. Run the following command to initialize the state with your s3 creds (from step 2): `tofu init -backend-config="secret_key=YOURSECRETKEY" -backend-config="access_key=YOURACCESSKEY"`
5. cheers. There's no state lock so try not to step on other people's toes pls ty 🤷