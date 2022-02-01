const express = require('express')
const app = express()
const port = 3000
const methodOverride = require('method-override')
const Article = require('./models/article')
const mongoose = require('mongoose');

require('dotenv').config();

const conn = process.env.DB_STRING;
mongoose.connect(conn, {useNewUrlParser: true, useUnifiedTopology: true})
.then( () =>console.log('DB Ok'))
.catch(err => console.log(err))


app.use(express.json())
app.use(express.urlencoded({extended: true}))
app.use(methodOverride('_method'))
app.use(express.static('public'))
app.use('/', require('./routes/routes'))
app.set('view engine', 'ejs')

app.get('/', (req, res) => {
    const articles = Article.find().sort({ createdAt: 'desc' })
    res.render('index', {
        articles: articles
    })
})

app.listen(port, () => console.log(`Example app listening on port ${port}!`))

