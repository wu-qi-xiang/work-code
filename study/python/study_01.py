def jiujiu():
    row = 1
    while row <=9:
        #print("%d" % row)
        col = 1
        while col <= row:
            #print("*", end="")
            print("%d * %d = %d" % (col,row,col*row), end="\t")
            col += 1
        row += 1
        print("")