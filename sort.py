#!/usr/bin/env python3


def greeting():
    print("Program to sort items in a file.")


def main():
    greeting()
    file_in = input("Name of file: ").lower()
    listicle = get_file(file_in)
    sorted_list = sort_list(listicle)
    file_out = f"{file_in.removesuffix('.txt')}.sorted.txt"
    print_file(sorted_list, file_out)
    print("done.")



def get_file(file_name):
    data_list = []
    with open(file_name, "r") as stream:
        for line in stream:
            data_list.append(line.title())

    return data_list


def sort_list(list_to_sort):
    return sorted(list_to_sort)


def print_file(out_list, filename):
    with open(filename, "w+") as write:
        for item in out_list:
            write.write(f"{item}")


if __name__ == "__main__":
    main()
