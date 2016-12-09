using Base.Test
ismatch(1:10, isodd, iseven, isodd, matchall=true) == [
	([1], [2], [3]),
	([5], [6], [7]),
]
ismatch("abcffedefgx", x-> x in ('d', 'e', 'f')) == (Any['f','f','e','d','e','f'],) ||
error("second failed")



_replace([1,2,3,4,5,6],
	(isodd,) => x -> 77
)

function test(a, b)
	if a == 10
		return b
	else
		return 77
	end
end

ast = Base.uncompressed_ast(code_lowered(test, (Int, Int))[])
isunless(x::Expr) = x.head == :gotoifnot
isunless(x) = false
islabelnode(x::LabelNode) = true
islabelnode(x) = false
function remove_goto(ast)
	_replace(ast, isunless, (x->true)*(*), islabelnode) do unless, body, label
		condition = unless[].args[1]
		Expr(:if, condition, remove_goto(body)...)
	end
end