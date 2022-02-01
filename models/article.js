const mongoose = require('mongoose');

const ArticleSchema = new mongoose.Schema({ 
    title: String,
    createdAt: { type: Date, default: Date.now },
    collectionName: String
});

const Article = mongoose.model('Article', ArticleSchema);

module.exports = Article;