from random import choice

worb_list = []
with open("/home/wulfalpha/sayings.txt", "r") as db:
    for line in db:
        worb_list.append(line.strip())

print(choice(worb_list))
