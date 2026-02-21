# scenarios/openstack-vm/Dockerfile
# 使用官方 Pulumi Python image 作 base，避免每次從頭下載安裝 Pulumi CLI
# Build: docker build -t <registry>/openstack-vm:latest .

FROM pulumi/pulumi-python:latest

WORKDIR /scenario

# 先安裝 Python 依賴（利用 Docker layer cache）
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 複製 Pulumi 程式碼
COPY Pulumi.yaml .
COPY __main__.py .
