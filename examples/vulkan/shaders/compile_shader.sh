SCRIPTPATH=$(cd "$(dirname "$0")" && pwd)

cd "$SCRIPTPATH"

glslc -fshader-stage=vert tri.vert -o tri.vert.spv
glslc -fshader-stage=frag tri.frag -o tri.frag.spv
