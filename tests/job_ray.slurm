#!/bin/bash
# shellcheck disable=SC2206

#SBATCH --job-name=Opt_ray
#SBATCH --output=res_ray.txt
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=80
#SBATCH --time=72:00:00
#SBATCH --mem=60000mb
#SBATCH --constraint=BEEOND

module purge
module load devel/python/3.11.7_intel_2021.4.0

export TMP_PATH="/mnt/odfs/${SLURM_JOB_ID}/stripe_1"
tar -C $TMP_PATH -xzf $(ws_find MC_train)/mix_data_shear.tar.gz
tar -C $TMP_PATH -xzf $(ws_find MC_train)/tensorflow_env.tar.gz
source $TMP_PATH/tensorflow/bin/activate
# __doc_head_address_start__

# Getting the node names
nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
nodes_array=($nodes)

head_node=${nodes_array[0]}
head_node_ip=$(srun --nodes=1 --ntasks=1 -w "$head_node" hostname --ip-address)

# if we detect a space character in the head node IP, we'll
# convert it to an ipv4 address. This step is optional.
if [[ "$head_node_ip" == *" "* ]]; then
IFS=' ' read -ra ADDR <<<"$head_node_ip"
if [[ ${#ADDR[0]} -gt 16 ]]; then
  head_node_ip=${ADDR[1]}
else
  head_node_ip=${ADDR[0]}
fi
echo "IPV6 address detected. We split the IPV4 address as $head_node_ip"
fi
# __doc_head_address_end__

# __doc_head_ray_start__
port=6379
ip_head=$head_node_ip:$port
export ip_head
echo "IP Head: $ip_head"

echo "Starting HEAD at $head_node"
srun --nodes=1 --ntasks=1 -w "$head_node" \
    ray start --head --node-ip-address="$head_node_ip" --port=$port \
    --num-cpus "${SLURM_CPUS_PER_TASK}" --num-gpus 0 --block &
# __doc_head_ray_end__

# __doc_worker_ray_start__
# optional, though may be useful in certain versions of Ray < 1.0.
sleep 10

# number of nodes other than the head node
worker_num=$((SLURM_JOB_NUM_NODES - 1))

for ((i = 1; i <= worker_num; i++)); do
    node_i=${nodes_array[$i]}
    echo "Starting WORKER $i at $node_i"
    srun --nodes=1 --ntasks=1 -w "$node_i" \
        ray start --address "$ip_head" \
        --num-cpus "${SLURM_CPUS_PER_TASK}" --num-gpus 0 --block &
    sleep 5
done
# __doc_worker_ray_end__

# __doc_script_start__
python -u ../pypbe/bond_break/ANN_parameter_study.py "$SLURM_CPUS_PER_TASK"

deactivate
