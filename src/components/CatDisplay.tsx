import React from 'react';
import { Heart, Gauge } from 'lucide-react';
import type { CatStats } from '../types/game';

interface CatDisplayProps {
  stats: CatStats;
}

export default function CatDisplay({ stats }: CatDisplayProps) {
  const getCatMood = () => {
    if (stats.mood > 80 && stats.health > 80) return 'happy';
    if (stats.mood < 30 || stats.health < 30) return 'sad';
    return 'neutral';
  };

  const catImages = {
    happy: 'https://images.unsplash.com/photo-1573865526739-10659fec78a5?w=400&q=80',
    neutral: 'https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=400&q=80',
    sad: 'https://images.unsplash.com/photo-1561948955-570b270e7c36?w=400&q=80',
  };

  return (
    <div className="w-full bg-white/90 rounded-xl shadow-lg backdrop-blur-sm p-4">
      <img
        src={catImages[getCatMood()]}
        alt="Your cat"
        className="w-32 h-32 mx-auto rounded-full object-cover border-4 border-pink-200 shadow-md"
      />
      
      <div className="mt-4 space-y-3">
        <div className="text-center">
          <span className="text-lg font-semibold text-gray-700">
            Day {Math.floor(stats.adoptionDays)}
          </span>
        </div>
        
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <Gauge className="w-5 h-5 text-green-500" />
            <div className="flex-1 h-4 bg-gray-200 rounded-full overflow-hidden">
              <div 
                className="h-full bg-green-500 transition-all duration-500"
                style={{ width: `${stats.health}%` }}
              />
            </div>
            <span className="text-sm font-medium text-gray-600">
              {Math.floor(stats.health)}%
            </span>
          </div>

          <div className="flex items-center gap-2">
            <Heart className="w-5 h-5 text-red-500" />
            <div className="flex-1 h-4 bg-gray-200 rounded-full overflow-hidden">
              <div 
                className="h-full bg-red-500 transition-all duration-500"
                style={{ width: `${stats.mood}%` }}
              />
            </div>
            <span className="text-sm font-medium text-gray-600">
              {Math.floor(stats.mood)}%
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}