# Compiler for P Language

## Summary

This is a simple compiler for self-defined `P` language, which can be viewed as a simplified version of `Pascal`. The whole skeleton of the compiler is as follows: 
![](https://github.com/controny/compiler-for-P/docs/skeleton.png)

## Syntax

Actually, this is the term project for my course *Intro. to Compiler Design*. So the syntax of `P` refers to the documents offered by our professor, which can be found in [docs](https://github.com/controny/compiler-for-P/docs).

## Usage

```
make && ./compile.sh [programname].p
java [programname]
```

## Example

Here is the code in `test.p`, which takes an integer as input and invokes a recursive function to calculate the corresponding Fibonacci Number:
```
// test.p

test;

fib( x: integer ): integer;
begin
	if x = 0 or x = 1 then
		return x;
	end if
	return fib(x-2) + fib(x-1);
end
end fib

begin
	var a, result: integer;
	print "Please enter an integer\n";
	read a;
	print "Fibonacci number F";
	print a;
	print " is ";
	print fib(a);
	print "\n";
end

end test
```
`make` the compiler and compile the above code:
```
make && ./compile.sh test.p
```
Then `test.class` is created and we use JVM to run it:
```
java test
```
We get the following result:
```shell
Please enter an integer
8
Fibonacci number F8 is 21

```