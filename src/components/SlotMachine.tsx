import React, { useState, useEffect, useRef } from 'react';
import { Play, Pause } from 'lucide-react';
import type { SlotSymbol, SlotResult } from '../types/game';
import { SYMBOLS } from '../types/game';
import { GAME_CONFIG } from '../config/game';

interface SlotMachineProps {
  isSpinning: boolean;
  autoSpin: boolean;
  onSpin: (results: SlotResult[]) => void;
  onAutoSpinToggle: () => void;
}

const REEL_SIZE = 4;
const REELS = 3;
const TOTAL_SYMBOLS = 12;
const SYMBOL_HEIGHT = 72; // 减小符号高度以适应手机屏幕

const getRandomSymbol = (): SlotSymbol => {
  const symbols = Object.entries(SYMBOLS);
  const totalChance = symbols.reduce((sum, [_, info]) => sum + info.chance, 0);
  let random = Math.random() * totalChance;
  
  for (const [symbol, info] of symbols) {
    random -= info.chance;
    if (random <= 0) {
      return symbol as SlotSymbol;
    }
  }
  
  return 'coin';
};

export default function SlotMachine({ 
  isSpinning, 
  autoSpin, 
  onSpin,
  onAutoSpinToggle 
}: SlotMachineProps) {
  const [reels, setReels] = useState<SlotSymbol[][]>(Array(REELS).fill([]).map(() => 
    Array(TOTAL_SYMBOLS).fill(null).map(() => getRandomSymbol())
  ));
  const [matchingRows, setMatchingRows] = useState<number[]>([]);
  const reelRefs = useRef<(HTMLDivElement | null)[]>([]);
  const spinOffset = useRef<number[]>(Array(REELS).fill(0));
  const animationFrame = useRef<number>();

  const findMatchingRows = (newReels: SlotSymbol[][]) => {
    const matches: number[] = [];
    
    for (let row = 0; row < REEL_SIZE; row++) {
      const rowSymbol = newReels[0][row];
      const isFullMatch = newReels.every(reel => reel[row] === rowSymbol);
      
      if (isFullMatch) {
        matches.push(row);
      }
    }
    
    return matches;
  };

  const spinReel = () => {
    const results: SlotResult[] = [];
    const newReels = Array(REELS).fill([]).map(() => {
      const reelSymbols = Array(TOTAL_SYMBOLS).fill(null).map(() => getRandomSymbol());
      results.push({
        symbol: reelSymbols[0],
        value: SYMBOLS[reelSymbols[0]].value
      });
      return reelSymbols;
    });

    spinOffset.current = spinOffset.current.map(offset => {
      const newOffset = offset - SYMBOL_HEIGHT;
      return newOffset;
    });
    
    setReels(newReels);
    
    setTimeout(() => {
      setMatchingRows(findMatchingRows(newReels));
    }, GAME_CONFIG.animation.stopDuration + 100);

    return results;
  };

  const handleSpin = () => {
    if (isSpinning) return;
    
    if (animationFrame.current) {
      cancelAnimationFrame(animationFrame.current);
    }
    
    const results = spinReel();
    onSpin(results);
  };

  useEffect(() => {
    let interval: NodeJS.Timeout;
    if (autoSpin && !isSpinning) {
      interval = setInterval(handleSpin, GAME_CONFIG.animation.spinInterval);
    }
    return () => {
      clearInterval(interval);
      if (animationFrame.current) {
        cancelAnimationFrame(animationFrame.current);
      }
    };
  }, [autoSpin, isSpinning]);

  return (
    <div className="w-full bg-gradient-to-b from-purple-600 to-purple-800 p-4 rounded-xl shadow-xl">
      <div className="grid grid-cols-3 gap-2 mb-4">
        {reels.map((reel, reelIndex) => (
          <div 
            key={reelIndex}
            className="relative h-72 bg-white/90 rounded-lg overflow-hidden shadow-inner"
          >
            <div className="reel-container" style={{ height: `${SYMBOL_HEIGHT * 4}px` }}>
              <div 
                ref={el => reelRefs.current[reelIndex] = el}
                className={`reel-strip ${
                  isSpinning 
                    ? 'animate-spin-reel' 
                    : 'animate-stop-reel'
                }`}
                style={{ 
                  '--spin-duration': `${GAME_CONFIG.animation.spinDuration}s`,
                  transform: `translateY(${spinOffset.current[reelIndex]}px)`,
                  transitionDelay: `${reelIndex * GAME_CONFIG.animation.reelStagger}s`
                } as React.CSSProperties}
              >
                {reel.map((symbol, symbolIndex) => {
                  const isMatchingRow = matchingRows.includes(symbolIndex % REEL_SIZE);
                  
                  return (
                    <div
                      key={symbolIndex}
                      className={`h-[72px] w-full flex items-center justify-center text-4xl transition-all duration-300
                        ${isMatchingRow ? 'scale-110 animate-pulse bg-yellow-100 shadow-lg' : ''}`}
                    >
                      <div className={`transform transition-all duration-300 
                        ${isMatchingRow ? 'scale-110 rotate-3' : ''}`}>
                        {SYMBOLS[symbol].icon}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        ))}
      </div>
      
      <div className="flex gap-2">
        <button
          onClick={handleSpin}
          disabled={isSpinning}
          className="flex-1 bg-yellow-400 hover:bg-yellow-500 text-yellow-900 font-bold py-3 px-6 rounded-lg
            shadow-lg transform active:scale-95 transition-all disabled:opacity-50 disabled:cursor-not-allowed"
        >
          SPIN!
        </button>
        
        <button
          onClick={onAutoSpinToggle}
          className={`w-14 flex items-center justify-center rounded-lg shadow-lg transform 
            active:scale-95 transition-all ${
              autoSpin ? 'bg-red-500 hover:bg-red-600' : 'bg-green-500 hover:bg-green-600'
            }`}
        >
          {autoSpin ? (
            <Pause className="w-6 h-6 text-white" />
          ) : (
            <Play className="w-6 h-6 text-white" />
          )}
        </button>
      </div>
    </div>
  );
}