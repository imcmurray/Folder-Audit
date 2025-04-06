const express = require('express');
const nano = require('nano')('http://localhost:5984'); // Adjust CouchDB URL
const app = express();
app.use(express.json());

const db = nano.use('folder_decisions'); // Your CouchDB database name

app.post('/submit', async (req, res) => {
    try {
        const { user, decisions } = req.body;
        await db.insert({ user, decisions, timestamp: new Date().toISOString() });
        res.status(200).send('Success');
    } catch (error) {
        console.error(error);
        res.status(500).send('Error');
    }
});

app.listen(3000, () => console.log('Server running on port 3000'));
