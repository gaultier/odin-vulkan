all: vert.spv frag.spv

vert.spv: shader.vert
	glslc $< -o $@

frag.spv: shader.frag
	glslc $< -o $@

.PHONY: all
