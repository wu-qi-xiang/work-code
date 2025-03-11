package main

import "fmt"

func wx(a string, b string) (string, int) {
	var my [10]int
	fmt.Println(my)
	fmt.Println("a = ",a)
	fmt.Println("b = ",b)
	c := "abd"
	d := 123
	return c,d
}

func main()  {
	fmt.Println("1234")
	c,d := wx("1","2")
	fmt.Println(c,d)
}