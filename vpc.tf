resource "aws_vpc" "this" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "flask-igw"
  }
}

resource "aws_route_table" "this" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "flask-rt"
  }
}

resource "aws_subnet" "this" {
  count = 2
  vpc_id     = aws_vpc.this.id
  cidr_block = "10.0.${count.index}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
}


resource "aws_route_table_association" "this" {
  count = 2
  subnet_id      = aws_subnet.this[count.index].id
  route_table_id = aws_route_table.this.id
}


data "aws_availability_zones" "available" {
  state = "available"
}

