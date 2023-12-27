vert.spv: shader.vert
	glslc $< -o $@

frag.spv: shader.frag
	glslc $< -o $@
