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