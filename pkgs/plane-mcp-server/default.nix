{
  python3Packages,
  fetchPypi,
}:

let
  plane-sdk = python3Packages.buildPythonPackage rec {
    pname = "plane_sdk";
    version = "0.2.8";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-qMSKvwV6yiSPtpE/5ucmPbMsFrXqwyjS2LnZvio+ots=";
    };

    build-system = [ python3Packages.setuptools ];

    dependencies = with python3Packages; [
      requests
      pydantic
    ];

    pythonImportsCheck = [ "plane" ];
  };
in
python3Packages.buildPythonApplication rec {
  pname = "plane_mcp_server";
  version = "0.2.8";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-iPdLzJ6e8MN6DQ1QKr+pXZS3Pgk6R+kzJa6Jt0/BhNI=";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies = with python3Packages; [
    fastmcp
    plane-sdk
    py-key-value-aio
    mcp
  ];

  pythonRelaxDeps = true;

  pythonImportsCheck = [ "plane_mcp" ];

  meta = {
    description = "Model Context Protocol server for Plane project management integration";
    homepage = "https://pypi.org/project/plane-mcp-server/";
    mainProgram = "plane-mcp-server";
  };
}
