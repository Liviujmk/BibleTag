const express = require('express');
const router = express.Router();
const mongoose = require('mongoose');
const Article = require('../models/article');

router.get('/:title', (req, res) => {
    const article = Article.findOne({ title: req.params.title })
    res.render('article', {
        article: article
    })
})

router.get('new', (req, res) => {
    res.render('new')
})

module.exports = router;