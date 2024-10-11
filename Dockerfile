FROM python:3

WORKDIR /simpleflask

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

ENV FLASK_APP=simpleflask.py

CMD ["python", "-m", "flask", "run", "--host", "0.0.0.0"]
