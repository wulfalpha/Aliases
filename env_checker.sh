#!/bin/bash

# env_checker.sh - A utility to display environment variables
# Usage: ./env_checker.sh [search_term]

print_header() {
    echo -e "\n\033[1;34m==== $1 ====\033[0m\n"
}

# Function to display all environment variables in a formatted way
show_all_env_vars() {
    print_header "All Environment Variables"
