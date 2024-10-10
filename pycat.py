#!/usr/bin/env python3
from random import randint


def generate_pawprint_pattern():
    # Define the size of the grid
    rows, cols = 10, 40

    # Create an empty grid
    grid = [[" " for _ in range(cols)] for _ in range(rows)]

    # Define the number of pawprints
    num_pawprints = 4

    # Randomly place pawprints on the grid
    for _ in range(num_pawprints):
        row = randint(0, rows - 2)
        col = randint(0, cols - 2)
        grid[row][col] = "🐾"

    # Convert grid to string for printing
    grid_str = "\n".join(["".join(row) for row in grid])

    return grid_str


def print_cat_with_pawprints():
    pawprint_pattern = generate_pawprint_pattern()
    cat_face = "*ฅ^•ﻌ•^ฅ*"

    # Print the pawprint pattern followed by the cat face
    print(pawprint_pattern)
    print(cat_face)


if __name__ == "__main__":
    print_cat_with_pawprints()
