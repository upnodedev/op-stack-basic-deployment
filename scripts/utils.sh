#!/bin/bash

# Function to derive address and check for conflicts
derive_and_check() {
  local key_var_name=$1
  local addr_var_name=$2
  local private_key=${!key_var_name}
  local passed_address=${!addr_var_name}

  if [ -n "$private_key" ]; then
    local derived_address
    derived_address=$(cast wallet address --private-key "$private_key")
    echo "$addr_var_name: $derived_address"

    if [ -n "$passed_address" ] && [ "$derived_address" != "$passed_address" ]; then
      echo "Error: Derived address for $addr_var_name conflicts with the passed address."
      exit 1
    fi

    export "$addr_var_name"="$derived_address"
  fi
}

#update_toml_value() {
#  local variable_name=$1
#  local new_value=$2
#  local file_name=$3
#
#  local escaped_value=$(printf '%s\n' "$new_value" | sed -e 's/[\/&]/\\&/g')
#
#  sed -i -e '/'"$variable_name"' =/ s/= .*/= '"$escaped_value"'/' "$file_name"
#}
